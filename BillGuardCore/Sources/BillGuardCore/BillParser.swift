//
//  BillParser.swift
//  BillGuardCore
//
//  Shared medical-bill parser — the exact logic from the iOS BillScannerView,
//  lifted out of the SwiftUI view so both the iOS and macOS apps use ONE parser.
//  Inputs are the four OCR region texts; the only external dependency (medical
//  code lookup) is injected as a closure. Produces a BillParseResult.
//

import Foundation

public struct BillParseResult {
    public var patientName = "", accountNumber = "", dateOfBirth = "", patientAddress = ""
    public var mrn = "", dischargeDate = "", admitDate = ""
    public var providerName = "", providerAddress = "", providerPhone = "", providerFax = ""
    public var providerEmail = "", providerWebsite = "", providerNPI = "", providerTaxId = "", providerLicense = ""
    public var insuranceCarrier = "", policyNumber = "", memberId = "", groupNumber = "", insurancePlanType = ""
    public var serviceDate = Date()
    public var billedAmount = "", totalCharges = "", insuranceAdjustment = "", insurancePaid = "", amountDue = ""
    public var lineItems: [ParsedLineItem] = []
    var detectedTemplate: ProviderBillTemplate?
}

public final class BillParser {
    private let patientText: String
    private let providerText: String
    private let insuranceText: String
    private let procedureText: String

    /// Medical-code lookup, injected by the app (e.g. backed by CloudKitService).
    /// Defaults to no matches so the parser is usable standalone / in tests.
    private let lookup: (String) -> MedicalCode?

    var serviceDate = Date()
    var patientName = "", accountNumber = "", dateOfBirth = "", patientAddress = ""
    var mrn = "", dischargeDate = "", admitDate = ""
    var detectedTemplate: ProviderBillTemplate?
    var providerName = "", providerAddress = "", providerPhone = "", providerFax = ""
    var providerEmail = "", providerWebsite = "", providerNPI = "", providerTaxId = "", providerLicense = ""
    var insuranceCarrier = "", policyNumber = "", memberId = "", groupNumber = "", insurancePlanType = ""
    var billedAmount = "", totalCharges = "", insuranceAdjustment = "", insurancePaid = "", amountDue = ""
    var lineItems: [ParsedLineItem] = []

    public init(patientText: String = "",
         providerText: String = "",
         insuranceText: String = "",
         procedureText: String = "",
         serviceDate: Date = Date(),
         lookup: @escaping (String) -> MedicalCode? = { _ in nil }) {
        self.patientText = patientText
        self.providerText = providerText
        self.insuranceText = insuranceText
        self.procedureText = procedureText
        self.serviceDate = serviceDate
        self.lookup = lookup
    }

    @discardableResult
    public func parse() -> BillParseResult {
        parsePatientFields()
        parseProviderFields()
        parseInsuranceFields()
        detectedTemplate = Self.findTemplate(for: providerName)
        parseLineItems()
        lookupLineItemCodes()
        if billedAmount.isEmpty && !lineItems.isEmpty {
            let total = lineItems.filter { $0.kind == .charge }.reduce(0) { $0 + $1.amount }
            billedAmount = String(format: "%.2f", total)
        }
        return BillParseResult(
            patientName: patientName, accountNumber: accountNumber, dateOfBirth: dateOfBirth,
            patientAddress: patientAddress, mrn: mrn, dischargeDate: dischargeDate, admitDate: admitDate,
            providerName: providerName, providerAddress: providerAddress, providerPhone: providerPhone,
            providerFax: providerFax, providerEmail: providerEmail, providerWebsite: providerWebsite,
            providerNPI: providerNPI, providerTaxId: providerTaxId, providerLicense: providerLicense,
            insuranceCarrier: insuranceCarrier, policyNumber: policyNumber, memberId: memberId,
            groupNumber: groupNumber, insurancePlanType: insurancePlanType,
            serviceDate: serviceDate, billedAmount: billedAmount, totalCharges: totalCharges,
            insuranceAdjustment: insuranceAdjustment, insurancePaid: insurancePaid, amountDue: amountDue,
            lineItems: lineItems, detectedTemplate: detectedTemplate)
    }

    // MARK: - Extracted parsing implementation (verbatim from BillScannerView)
    private func parsePatientFields() {
        let rawLines = patientText.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        
        // ── Filter postal/barcode artifacts ──
        let lines = rawLines.filter { line in
            let upper = line.uppercased()
            // Postal barcodes: start with > or contain long digit sequences like "TU25 1003 59569"
            if line.hasPrefix(">") { return false }
            if upper.contains("ADDRESS SERVICE") || upper.contains("ADDRESSEE") { return false }
            if upper.contains("RETURN SERVICE") || upper.contains("PRESORT") { return false }
            // Lines that are mostly digits with spaces (postal routing codes)
            let digitRatio = Double(line.filter { $0.isNumber }.count) / Double(max(line.count, 1))
            if digitRatio > 0.6 && line.count > 10 { return false }
            // Lines starting with barcode chars
            if line.hasPrefix("|") || line.hasPrefix("!") { return false }
            return true
        }
        
        let pairs = extractAllLabelValuePairs(from: lines)
        
        for (label, value) in pairs {
            let key = label.lowercased()
            if (key.contains("patient") || key.contains("name") || key.contains("insured") || key.contains("subscriber"))
                && !key.contains("address") && !key.contains("balance") && !key.contains("amount") {
                if patientName.isEmpty && looksLikeName(value) { patientName = value }
            } else if key.contains("account") || key.contains("acct") || key.contains("voucher") {
                if accountNumber.isEmpty { accountNumber = value }
            } else if key.contains("birth") || key == "dob" {
                if dateOfBirth.isEmpty { dateOfBirth = value }
            } else if key.contains("date of service") || key.contains("service date") || key == "dos" {
                if let date = parseDate(value) { serviceDate = date }
            } else if key.contains("address") {
                if patientAddress.isEmpty { patientAddress = value }
            } else if key == "mrn" || key.contains("medical record") {
                if mrn.isEmpty { mrn = value }
            } else if key.contains("discharge") {
                if dischargeDate.isEmpty { dischargeDate = value }
            }
        }
        
        // Fallback: two-line OCR pattern — label on one line, value on the next
        // e.g. "Date of Service:" / "11/10/2024"  or  "Patient:" / "John Smith"
        let datePattern = #"\d{1,2}[/-]\d{1,2}[/-]\d{2,4}"#
        for (i, line) in lines.enumerated() {
            guard i + 1 < lines.count else { break }
            let lower = line.lowercased().trimmingCharacters(in: .whitespaces)
            let next  = lines[i + 1].trimmingCharacters(in: .whitespaces)
            if (lower.hasPrefix("patient") || lower.hasPrefix("name")) && lower.hasSuffix(":")
                && patientName.isEmpty && looksLikeName(next) {
                patientName = next
            } else if (lower.contains("date of service") || lower.contains("service date") || lower == "dos:")
                && serviceDate == Date()
                && next.range(of: datePattern, options: .regularExpression) != nil {
                if let d = parseDate(next) { serviceDate = d }
            } else if lower.contains("account") && lower.hasSuffix(":")
                && accountNumber.isEmpty && !next.contains(":") {
                accountNumber = next
            } else if (lower == "mrn:" || lower == "medical record:") && mrn.isEmpty {
                mrn = next
            } else if lower.contains("admit") && lower.hasSuffix(":") && admitDate.isEmpty
                && next.range(of: datePattern, options: .regularExpression) != nil {
                admitDate = next
            } else if lower.contains("discharge") && lower.hasSuffix(":") && dischargeDate.isEmpty
                && next.range(of: datePattern, options: .regularExpression) != nil {
                dischargeDate = next
            }
        }

        // Fallback: find first name-like line (skip provider-looking headers)
        if patientName.isEmpty {
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.contains(":") { continue }
                // Skip lines that look like provider/facility headers
                let upper = trimmed.uppercased()
                if upper.contains("MEDICAL") || upper.contains("HOSPITAL") || upper.contains("CLINIC")
                    || upper.contains("HEALTH") || upper.contains("ASSOCIATES") || upper.contains("ASSOC") { continue }
                // Skip address lines
                if looksLikeAddress(trimmed) { continue }
                if looksLikeName(trimmed) {
                    patientName = trimmed; break
                }
            }
        }

        // Fallback 2: a name merged onto an address line, e.g.
        // "PO BOX 391402  MARY M ARSENAULT" — extract the longest run of
        // consecutive name-like words (skipping address/provider tokens).
        if patientName.isEmpty {
            let stop: Set<String> = ["PO", "BOX", "STREET", "ST", "AVE", "AVENUE",
                "ROAD", "RD", "SUITE", "STE", "DR", "LANE", "LN", "APT", "UNIT",
                "FL", "DELAND", "DELTONA", "MEDICAL", "HOSPITAL", "CLINIC", "ASSOC",
                "ASSOCIATES", "ADDRESSEE", "ADDRESS", "SERVICE", "REQUESTED",
                "STATEMENT", "PATIENT", "ACCOUNT", "VOUCHER"]
            for line in lines {
                var run: [String] = [], best: [String] = []
                for w in line.split(separator: " ").map(String.init) {
                    let isNameWord = (w.first?.isLetter == true)
                        && w.allSatisfy { $0.isLetter || $0 == "." || $0 == "'" || $0 == "-" }
                    if isNameWord, !stop.contains(w.uppercased()) {
                        run.append(w)
                        if run.count > best.count { best = run }
                    } else { run = [] }
                }
                if best.count >= 2 && best.count <= 4 {
                    patientName = best.joined(separator: " "); break
                }
            }
        }

        // Fallback: find address after patient name
        if patientAddress.isEmpty {
            var foundName = false
            for line in lines {
                if !patientName.isEmpty && line.uppercased().contains(patientName.uppercased()) {
                    foundName = true; continue
                }
                if foundName && looksLikeAddress(line) {
                    patientAddress = line
                    // Check if next line is city/state/ZIP continuation
                    if let idx = lines.firstIndex(of: line), idx + 1 < lines.count {
                        let next = lines[idx + 1]
                        if next.range(of: #"\b\d{5}(-\d{4})?\b"#, options: .regularExpression) != nil {
                            patientAddress += ", " + next
                        }
                    }
                    break
                }
            }
            // Broader fallback: any address-looking line
            if patientAddress.isEmpty {
                for line in lines {
                    if looksLikeAddress(line) {
                        patientAddress = line
                        if let idx = lines.firstIndex(of: line), idx + 1 < lines.count {
                            let next = lines[idx + 1]
                            if next.range(of: #"\b\d{5}(-\d{4})?\b"#, options: .regularExpression) != nil {
                                patientAddress += ", " + next
                            }
                        }
                        break
                    }
                }
            }
        }
    }
    
    // MARK: - Provider Parsing
    
    private func parseProviderFields() {
        // ── Credit-card / "pay by card" billing-box stripping ────────────────
        // A bill's provider region frequently sits next to a "IF PAYING BY
        // MASTERCARD…" box. OCR row-grouping merges the two (provider header on the
        // left, billing box on the right) into single lines. Strip the billing box
        // UP FRONT so NO downstream field — name, address, phone — can pick up its
        // text (CARDHOLDER NAME, EXP. DATE, etc.).
        let creditCardTerms: Set<String> = [
            "cardholder", "card holder", "card number", "cardnumber",
            "exp date", "exp. date", "expiration", "expiry",
            "verification", "cvv", "cvc", "security code",
            "signature", "mastercard", "visa", "amex",
            "american express", "discover", "credit card"
        ]
        func isCreditCardLine(_ line: String) -> Bool {
            let lower = line.lowercased()
            return creditCardTerms.contains(where: { lower.contains($0) })
        }

        // Markers that begin the billing box. Matched at word boundaries so e.g.
        // "VISA" doesn't clip "VISALIA" and "AMEX" doesn't clip a real word.
        let billingBoxMarkers = ["IF PAYING", "FILL OUT", "CHECK CARD", "USING FOR PAYMENT",
                                 "MASTERCARD", "VISA", "AMEX", "DISCOVER", "CARD NUMBER",
                                 "CARDHOLDER", "VERIFICATION", "EXP DATE", "EXP. DATE",
                                 "EXPIRATION", "SIGNATURE", "CVV", "CREDIT CARD",
                                 "RETURN THIS PORTION", "SHOW AMOUNT", "PAID HERE"]
        func strippedOfBillingBox(_ line: String) -> String {
            let upper = line.uppercased()
            let chars = Array(upper)
            var cut = chars.count
            for marker in billingBoxMarkers {
                guard let r = upper.range(of: marker) else { continue }
                let start = upper.distance(from: upper.startIndex, to: r.lowerBound)
                let end   = upper.distance(from: upper.startIndex, to: r.upperBound)
                let beforeOK = start == 0 || !chars[start - 1].isLetter
                let afterOK  = end >= chars.count || !chars[end].isLetter
                if beforeOK && afterOK && start < cut { cut = start }
            }
            guard cut < chars.count else { return line }
            let idx = line.index(line.startIndex, offsetBy: cut)
            return String(line[line.startIndex..<idx]).trimmingCharacters(in: .whitespaces)
        }

        // Fuzzy backstop for OCR-garbled billing labels the exact markers miss
        // (e.g. "SIGNATURE" → "SIONATURE", "AMOUNT" surviving alone). Drop any line
        // containing a word that's a near-match (edit-distance-tolerant) to a
        // distinctive billing-box field label. These never appear in a real
        // provider letterhead, so this can't discard a genuine name/address.
        let strongBillingWords = ["CARDHOLDER", "SIGNATURE", "VERIFICATION",
                                  "MASTERCARD", "EXPIRATION", "AMOUNT"]
        func isBillingNoise(_ line: String) -> Bool {
            let words = line.uppercased().split { !$0.isLetter }
                .map(String.init).filter { $0.count >= 4 }
            return words.contains { w in
                strongBillingWords.contains { descriptionSimilarity(w, $0) >= 0.82 }
            }
        }

        // Cleaned line set used by EVERY step below: billing box stripped per line,
        // then empties / pure-billing / billing-noise lines dropped.
        let lines = providerText.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .map { strippedOfBillingBox($0) }
            .filter { !$0.isEmpty && !isCreditCardLine($0) && !isBillingNoise($0) }
        let pairs = extractAllLabelValuePairs(from: lines)

        // Medical facility keywords — if a line contains any of these, it's likely a provider name
        let facilityKeywords = ["MEDICAL CENTER", "HOSPITAL", "HEALTH SYSTEM", "HEALTH CENTER",
                                "REGIONAL MEDICAL", "CLINIC", "SURGICAL CENTER", "URGENT CARE",
                                "MEMORIAL", "COMMUNITY HEALTH", "MEDICAL GROUP", "PHYSICIANS",
                                "HEALTHCARE", "AMBULATORY", "IMAGING CENTER", "RADIOLOGY",
                                "LABORATORY", "PATHOLOGY", "ORTHOPAEDIC", "ORTHOPEDIC",
                                // Extended — family/general practices & wellness centers
                                "FAMILY MEDICINE", "INTERNAL MEDICINE", "MEDICINE & WELLNESS",
                                "FAMILY PRACTICE", "FAMILY HEALTH", "MEDICAL ASSOC",
                                "WELLNESS CENTER", "WELLNESS CLINIC", "HEALTH & WELLNESS",
                                "MEDICAL PRACTICE", "MEDICAL SERVICES", "HEALTH SERVICES",
                                "CARE CENTER", "CARE CLINIC", "WOMEN'S HEALTH", "WOMEN'S CARE",
                                "PEDIATRICS", "DERMATOLOGY", "CARDIOLOGY", "NEUROLOGY",
                                "ONCOLOGY", "UROLOGY", "GASTROENTEROLOGY", "PULMONOLOGY",
                                "ENDOCRINOLOGY", "RHEUMATOLOGY", "NEPHROLOGY", "HEMATOLOGY"]

        // (billing box already stripped above — `lines`/`pairs` are clean)
        let filteredLines = lines
        let filteredPairs = pairs

        // ── Step 1: Extract labeled fields (credit-card fields excluded) ──
        for (label, value) in filteredPairs {
            let key = label.lowercased()
            if key.contains("provider") || key.contains("facility") || key.contains("hospital") || key.contains("clinic") {
                if providerName.isEmpty { providerName = value }
            } else if key.contains("remit") || key.contains("pay to") || key.contains("send to") || key.contains("return to") || key.contains("bill to") {
                if providerName.isEmpty && looksLikeName(value) { providerName = value }
            } else if key.contains("fax") {
                if providerFax.isEmpty { providerFax = value }
            } else if key.contains("phone") || key.contains("tel") || key.contains("office phone") {
                if providerPhone.isEmpty { providerPhone = value }
            } else if key.contains("email") || key.contains("e-mail") {
                if providerEmail.isEmpty { providerEmail = value }
            } else if key.contains("web") || key.contains("url") || key.contains("site") {
                if providerWebsite.isEmpty { providerWebsite = value }
            } else if key.contains("npi") {
                if providerNPI.isEmpty { providerNPI = value }
            } else if key.contains("tax") || key.contains("ein") || (key.contains("fed") && key.contains("id")) {
                if providerTaxId.isEmpty { providerTaxId = value }
            } else if key.contains("license") || key.contains("lic") {
                if providerLicense.isEmpty { providerLicense = value }
            } else if key.contains("address") && !key.contains("account") {
                if providerAddress.isEmpty { providerAddress = value }
            }
        }
        
        // ── Step 2: Detect facility name by medical keywords (using filtered lines) ──
        if providerName.isEmpty {
            for line in filteredLines {
                let upper = line.uppercased()
                if looksLikeFilename(line) || looksLikeProcedureRow(line) { continue }   // skip filename/window chrome & charges rows
                if facilityKeywords.contains(where: { upper.contains($0) }) {
                    var name = line
                    // Strip statement/department labels that may be on the same line
                    let stripPatterns = ["EMERGENCY DEPT STATEMENT", "INPATIENT STATEMENT",
                                         "OUTPATIENT STATEMENT", "PATIENT STATEMENT",
                                         "BILLING STATEMENT", "EMERGENCY DEPARTMENT"]
                    for pattern in stripPatterns {
                        if let range = name.uppercased().range(of: pattern) {
                            let startIdx = name.index(name.startIndex, offsetBy: name.distance(from: name.startIndex, to: range.lowerBound))
                            name = String(name[name.startIndex..<startIdx]).trimmingCharacters(in: .whitespaces)
                        }
                    }
                    // Strip a LEADING street-address segment when OCR merged
                    // "1070 NORTH STONE STREET SUITE  WEST VOLUSIA MEDICAL ASSOCIAT"
                    // (street first, name after). Requires a leading street number so
                    // it can't eat a normal facility name.
                    let streetSuffix = #"(STREET|ST|AVENUE|AVE|ROAD|RD|BLVD|DRIVE|DR|LANE|LN|SUITE|STE|WAY|COURT|CT|PLACE|PL|HWY|HIGHWAY|PIKE|CIRCLE|CIR|BOX)"#
                    if let r = name.range(of: "^\\s*\\d{1,6}\\s+.*\\b\(streetSuffix)\\b\\.?\\s+",
                                          options: [.regularExpression, .caseInsensitive]) {
                        let stripped = String(name[r.upperBound...]).trimmingCharacters(in: .whitespaces)
                        if !stripped.isEmpty,
                           facilityKeywords.contains(where: { stripped.uppercased().contains($0) }) {
                            name = stripped
                        }
                    }
                    // Strip a TRAILING street-address segment (name then street)
                    if let addrRange = name.range(of: #"\s+\d{2,5}\s+[A-Za-z]"#, options: .regularExpression) {
                        let afterAddr = String(name[addrRange.lowerBound...])
                        if looksLikeAddress(afterAddr) {
                            name = String(name[name.startIndex..<addrRange.lowerBound]).trimmingCharacters(in: .whitespaces)
                        }
                    }
                    name = name.trimmingCharacters(in: .whitespaces)
                    // No looksLikeAddress guard here: this line CONTAINS a facility
                    // keyword, so it IS the provider name — even if it contains a
                    // directional word like "WEST"/"NORTH" that looksLikeAddress flags.
                    if !name.isEmpty {
                        providerName = name
                        break
                    }
                }
            }
        }
        
        // ── Step 3: Parse combined Phone/Fax lines ──
        let phonePattern = #"\(?\d{3}\)?[-.\s]?\d{3}[-.\s]?\d{4}"#
        for line in lines {
            // Split "Phone: (407) 555-0100 | Fax: (407) 555-0101"
            let parts = line.components(separatedBy: "|")
            for part in parts {
                let partLower = part.lowercased().trimmingCharacters(in: .whitespaces)
                if partLower.contains("fax") && providerFax.isEmpty {
                    if let range = part.range(of: phonePattern, options: .regularExpression) {
                        providerFax = String(part[range])
                    }
                } else if (partLower.contains("phone") || partLower.contains("tel")) && providerPhone.isEmpty {
                    if let range = part.range(of: phonePattern, options: .regularExpression) {
                        providerPhone = String(part[range])
                    }
                }
            }
        }
        
        // ── Step 4: REMIT TO address collection ──
        // Collect address lines after a REMIT TO / PAY TO marker.
        // IMPORTANT: address lines (e.g. "1070 N STONE ST") must NOT be used
        // to overwrite providerName. Only set providerName from lines that
        // explicitly look like a facility name AND come BEFORE any address line.
        if providerAddress.isEmpty {
            var foundRemit = false
            var addressParts: [String] = []
            var nameBeforeAddress: String? = nil
            for line in filteredLines {
                if isCreditCardLine(line) { continue }
                let lower = line.lowercased()
                if lower.contains("remit to") || lower.contains("pay to") || lower.contains("send to")
                    || lower.contains("return to") || lower.contains("bill to") {
                    foundRemit = true
                    // Inline value after the marker label
                    if let colonIdx = line.firstIndex(of: ":") {
                        let after = String(line[line.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)
                        if !after.isEmpty && providerName.isEmpty && looksLikeName(after) {
                            nameBeforeAddress = after
                        }
                    }
                    continue
                }
                if foundRemit {
                    let isAddr = looksLikeAddress(line)
                        || line.range(of: #"\b\d{5}(-\d{4})?\b"#, options: .regularExpression) != nil
                    if isAddr {
                        // Commit the name candidate now that we know the next line IS an address
                        if let n = nameBeforeAddress, providerName.isEmpty { providerName = n }
                        nameBeforeAddress = nil
                        addressParts.append(line)
                    } else if addressParts.isEmpty && !looksLikePhone(line) && !line.contains(":") && line.count > 3 {
                        // Candidate name line before any address has been seen
                        if looksLikeName(line) { nameBeforeAddress = line }
                    } else if !addressParts.isEmpty {
                        // Continuation address line or end-of-block
                        if looksLikeAddress(line) || line.range(of: #"\b\d{5}(-\d{4})?\b"#, options: .regularExpression) != nil {
                            addressParts.append(line)
                        } else {
                            break
                        }
                    }
                }
            }
            if !addressParts.isEmpty {
                providerAddress = addressParts.joined(separator: ", ")
            }
        }
        // ── Step 5: Fallback — first non-label, non-phone, non-address line ──
        if providerName.isEmpty {
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                // Strip the billing box first so a name merged onto the same OCR row
                // ("WEST VOLUSIA MEDICAL ASSOCIAT   IF PAYING BY MASTERCARD…") keeps
                // the name rather than being discarded for containing "MASTERCARD".
                var candidateLine = strippedOfBillingBox(trimmed)
                if candidateLine.isEmpty { continue }
                // Strip any trailing document-type label (e.g. "PATIENT STATEMENT")
                // before deciding whether to skip this line, so that a provider name
                // like "ORLANDO FAMILY MEDICINE & WELLNESS    PATIENT STATEMENT" is
                // not discarded just because the label happens to land on the same line.
                let statementLabels = ["PATIENT STATEMENT", "BILLING STATEMENT",
                                       "INPATIENT STATEMENT", "OUTPATIENT STATEMENT",
                                       "EMERGENCY DEPT STATEMENT", "ACCOUNT STATEMENT"]
                for label in statementLabels {
                    if let range = candidateLine.uppercased().range(of: label) {
                        let stripped = String(candidateLine[candidateLine.startIndex..<range.lowerBound])
                            .trimmingCharacters(in: .whitespaces)
                        if !stripped.isEmpty { candidateLine = stripped }
                    }
                }
                let candidateUpper = candidateLine.uppercased()
                // Now apply the original skip guards on the cleaned candidate
                if candidateUpper.contains("STATEMENT") && !facilityKeywords.contains(where: { candidateUpper.contains($0) }) { continue }
                if looksLikeFilename(candidateLine) || looksLikeProcedureRow(candidateLine) { continue }   // skip filename/window chrome & charges rows
                if !candidateLine.contains(":") && candidateLine.count > 3 && !looksLikePhone(candidateLine) && !looksLikeAddress(candidateLine) {
                    providerName = candidateLine; break
                }
            }
        }
        
        // ── Step 5b: Longest-line fallback ──
        // If Steps 1–5 all failed (common with severely garbled dark-bg OCR),
        // pick the longest line that:
        //   • is all-caps or title-case (typical for a facility header)
        //   • is NOT an address or phone number
        //   • is NOT a known statement label
        if providerName.isEmpty {
            let statementWords = ["STATEMENT", "INVOICE", "RECEIPT", "NOTICE", "ACCOUNT"]
            let candidates = lines.filter { line in
                let t = line.trimmingCharacters(in: .whitespaces)
                guard t.count > 5, !t.contains(":"),
                      !looksLikeAddress(t), !looksLikePhone(t),
                      !looksLikeFilename(t), !looksLikeProcedureRow(t) else { return false }
                let upper = t.uppercased()
                if statementWords.contains(where: { upper.contains($0) }) { return false }
                // Must look like a name: mostly letters, spaces, &, ., -
                let nonNameChars = t.filter { !$0.isLetter && !$0.isWhitespace && !"&.-,'".contains($0) }
                return Double(nonNameChars.count) / Double(max(t.count, 1)) < 0.15
            }
            if let best = candidates.max(by: { $0.count < $1.count }) {
                // Apply statement-label strip one more time
                var name = best
                let statementLabels = ["PATIENT STATEMENT", "BILLING STATEMENT",
                                       "INPATIENT STATEMENT", "OUTPATIENT STATEMENT",
                                       "EMERGENCY DEPT STATEMENT", "ACCOUNT STATEMENT"]
                for label in statementLabels {
                    if let r = name.uppercased().range(of: label) {
                        let stripped = String(name[name.startIndex..<r.lowerBound])
                            .trimmingCharacters(in: .whitespaces)
                        if !stripped.isEmpty { name = stripped }
                    }
                }
                if !name.isEmpty { providerName = name }
            }
        }

        // ── Step 6: Collect address by scanning for address-pattern lines ──
        if providerAddress.isEmpty {
            var addressParts: [String] = []
            var collecting = false
            for line in lines {
                // Never treat the facility name as address — looksLikeAddress can
                // be fooled by a directional word ("WEST VOLUSIA…"). The name has a
                // facility keyword; the street address does not.
                if facilityKeywords.contains(where: { line.uppercased().contains($0) })
                    || line.caseInsensitiveCompare(providerName) == .orderedSame {
                    continue
                }
                if looksLikeAddress(line) {
                    addressParts.append(line)
                    collecting = true
                } else if collecting {
                    if line.range(of: #"\b\d{5}(-\d{4})?\b"#, options: .regularExpression) != nil {
                        addressParts.append(line)
                    }
                    break
                }
            }
            if !addressParts.isEmpty {
                providerAddress = addressParts.joined(separator: ", ")
            }
        }
        
        // ── Step 7: Remaining standalone fields ──
        if providerPhone.isEmpty {
            for line in lines {
                if looksLikePhone(line) {
                    if let range = line.range(of: phonePattern, options: .regularExpression) {
                        providerPhone = String(line[range])
                    } else {
                        providerPhone = line
                    }
                    break
                }
            }
        }
        if providerEmail.isEmpty {
            let emailPattern = #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#
            for line in lines {
                if let range = line.range(of: emailPattern, options: .regularExpression) {
                    providerEmail = String(line[range]); break
                }
            }
        }
        if providerWebsite.isEmpty {
            let webPattern = #"(?:https?://|www\.)[A-Za-z0-9._~:/?#\[\]@!$&'()*+,;=-]+"#
            for line in lines {
                if let range = line.range(of: webPattern, options: .regularExpression) {
                    providerWebsite = String(line[range]); break
                }
            }
        }
        if providerFax.isEmpty {
            for line in lines {
                if line.lowercased().contains("fax") {
                    if let range = line.range(of: phonePattern, options: .regularExpression) {
                        providerFax = String(line[range]); break
                    }
                }
            }
        }
        if providerNPI.isEmpty {
            for line in lines {
                if line.lowercased().contains("npi") {
                    if let range = line.range(of: #"\b\d{10}\b"#, options: .regularExpression) {
                        providerNPI = String(line[range]); break
                    }
                }
            }
        }
        if providerTaxId.isEmpty {
            for line in lines {
                let lower = line.lowercased()
                if lower.contains("tax") || lower.contains("ein") || lower.contains("fed") {
                    if let range = line.range(of: #"\b\d{2}-?\d{7}\b"#, options: .regularExpression) {
                        providerTaxId = String(line[range]); break
                    }
                }
            }
        }
        
        // ── Step 8: Cross-scan other regions for provider if still empty ──
        // NOTE: procedureText is deliberately excluded — the charges table contains
        // CPT descriptions ("Initial Hospital Care", "Hospital Discharge Day") that
        // match the "HOSPITAL" facility keyword and would be mistaken for the name.
        if providerName.isEmpty {
            let allTexts = [patientText, insuranceText]
            for regionText in allTexts {
                let regionLines = regionText.components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                for line in regionLines {
                    let upper = line.uppercased()
                    if looksLikeProcedureRow(line) || looksLikeFilename(line) { continue }
                    if facilityKeywords.contains(where: { upper.contains($0) }) {
                        var name = line
                        let stripPatterns = ["EMERGENCY DEPT STATEMENT", "INPATIENT STATEMENT",
                                             "OUTPATIENT STATEMENT", "PATIENT STATEMENT",
                                             "BILLING STATEMENT", "EMERGENCY DEPARTMENT"]
                        for pattern in stripPatterns {
                            if let range = name.uppercased().range(of: pattern) {
                                let startIdx = name.index(name.startIndex, offsetBy: name.distance(from: name.startIndex, to: range.lowerBound))
                                name = String(name[name.startIndex..<startIdx]).trimmingCharacters(in: .whitespaces)
                            }
                        }
                        if !name.isEmpty { providerName = name }
                        break
                    }
                }
                if !providerName.isEmpty { break }
            }
        }

        // ── Step 9: Correct a misread state code in the address (e.g. "FR" → "FL") ──
        if !providerAddress.isEmpty {
            providerAddress = correctStateCode(in: providerAddress)
        }

        #if DEBUG
        print("── Provider parsed: name=\"\(providerName)\" phone=\"\(providerPhone)\" fax=\"\(providerFax)\" addr=\"\(providerAddress)\"")
        #endif
    }
    
    // MARK: - Insurance Parsing
    
    private func parseInsuranceFields() {
        let lines = insuranceText.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let pairs = extractAllLabelValuePairs(from: lines)
        
        for (label, value) in pairs {
            let key = label.lowercased()
            if key.contains("insurance") || key.contains("carrier") || key.contains("payer") || key.contains("plan name") {
                if insuranceCarrier.isEmpty { insuranceCarrier = value }
            } else if key.contains("policy") {
                if policyNumber.isEmpty { policyNumber = value }
            } else if key.contains("member") || key.contains("subscriber id") || (key == "id" && memberId.isEmpty) {
                if memberId.isEmpty { memberId = value }
            } else if key.contains("group") {
                if groupNumber.isEmpty { groupNumber = value }
            } else if key.contains("plan type") || key.contains("type") {
                if insurancePlanType.isEmpty { insurancePlanType = value }
            } else if key == "mrn" || key.contains("medical record") {
                if mrn.isEmpty { mrn = value }
            } else if key.contains("discharge") {
                if dischargeDate.isEmpty { dischargeDate = value }
            } else if key.contains("admit") {
                if admitDate.isEmpty { admitDate = value }
            }
        }
        
        // Also scan patient text for MRN (it often appears there)
        if mrn.isEmpty {
            let patientPairs = extractAllLabelValuePairs(from:
                patientText.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            )
            for (label, value) in patientPairs {
                let key = label.lowercased()
                if key == "mrn" || key.contains("medical record") {
                    mrn = value; break
                }
            }
        }
        
        // Scan all regions for discharge date if not found in insurance
        if dischargeDate.isEmpty {
            let allRegionTexts = [patientText, providerText, procedureText]
            for regionText in allRegionTexts {
                let regionPairs = extractAllLabelValuePairs(from:
                    regionText.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                )
                for (label, value) in regionPairs {
                    let key = label.lowercased()
                    if key.contains("discharge") {
                        dischargeDate = value; break
                    }
                }
                if !dischargeDate.isEmpty { break }
            }
        }
        
        // Detect plan type from any line (HMO, PPO, etc.)
        if insurancePlanType.isEmpty {
            let allText = insuranceText.uppercased()
            let planPatterns = ["HMO", "PPO", "EPO", "POS", "HDHP", "MEDICARE", "MEDICAID", "TRICARE"]
            for p in planPatterns {
                if allText.contains(p) { insurancePlanType = p; break }
            }
        }
        
        // Fallback: first non-label, non-provider, non-credit-card line = carrier name
        if insuranceCarrier.isEmpty {
            let providerFacilityKeywords = [
                "MEDICAL CENTER", "HOSPITAL", "HEALTH SYSTEM", "CLINIC", "SURGICAL",
                "MEDICAL GROUP", "PHYSICIANS", "HEALTHCARE", "ASSOCIATES", "MEDICAL"
            ]
            let ccTerms = ["CARDHOLDER", "CARD NUMBER", "EXP DATE", "EXPIRATION",
                          "MASTERCARD", "VISA", "SIGNATURE", "VERIFICATION"]
            // Statement-structure / header labels that are not a carrier name.
            let statementNoise = ["ACCOUNT", "PATIENT BALANCE", "SHOW AMOUNT", "PAID HERE",
                                  "STATEMENT", "RETURN THIS", "DUE DATE", "STATEMENT DATE",
                                  "REMIT", "OFFICE PHONE", "PAGE ", "BALANCE", "AMOUNT"]
            for line in lines {
                let upper = line.uppercased()
                guard !line.contains(":"), line.count > 3 else { continue }
                guard !providerFacilityKeywords.contains(where: { upper.contains($0) }) else { continue }
                guard !ccTerms.contains(where: { upper.contains($0) }) else { continue }
                guard !statementNoise.contains(where: { upper.contains($0) }) else { continue }
                guard !looksLikeAddress(line), !looksLikePhone(line) else { continue }
                insuranceCarrier = line; break
            }
        }
    }
    
    // MARK: - Template Detection

    /// Built-in templates. More can be added here as new provider formats are encountered.
    private static let builtInTemplates: [ProviderBillTemplate] = [
        {
            var t = ProviderBillTemplate(
                displayName: "West Volusia Medical Associates",
                matchKeywords: ["west volusia", "volusia medical", "volusia medical assoc"]
            )
            t.billFormat = .accountStatement
            var layout = ProcedureColumnLayout()
            layout.chargesColumnKeywords    = ["charges", "debits", "charges & debits"]
            layout.insurancePendingKeywords = ["insurance pending", "ins pending"]
            layout.paymentsColumnKeywords   = ["payments", "credits", "payments & credits"]
            layout.patientAmountKeywords    = ["patient amount", "patient", "pt amount"]
            layout.visitTotalLabels         = ["visit total", "---- visit total", "---visit total"]
            layout.voucherLabels            = ["voucher:", "voucher #"]
            layout.accountingRowKeywords    = [
                "payment", "adjustment", "transfer", "credit card", "self pay",
                "mastercard", "visa", "check", "write off", "write-off",
                "courtesy", "refund", "cigna", "aetna", "humana", "bcbs",
                "blue cross", "united health", "anthem", "collection"
            ]
            t.procedureColumnLayout = layout
            return t
        }()
    ]

    /// Returns the matching provider template for a given provider name.
    /// Checks UserDefaults-persisted templates first, then built-ins.
    static func findTemplate(for providerName: String) -> ProviderBillTemplate? {
        let lower = providerName.lowercased()

        // Check UserDefaults for user-saved templates
        if let data = UserDefaults.standard.data(forKey: "ProviderBillTemplates_v1"),
           let saved = try? JSONDecoder().decode([ProviderBillTemplate].self, from: data) {
            if let match = saved.first(where: { t in
                t.matchKeywords.contains(where: { lower.contains($0.lowercased()) })
            }) { return match }
        }

        // Fall back to built-ins
        return builtInTemplates.first { t in
            t.matchKeywords.contains(where: { lower.contains($0.lowercased()) })
        }
    }

    // MARK: - Line Item Parsing

    /// Detects the multi-column "account statement" layout from its distinctive
    /// headers/rows so the column-aware parser runs even when the provider-name OCR
    /// is too poor to match a template. ≥2 signals required (standard itemized bills
    /// have none of these), so it can't false-positive on a normal bill.
    private func looksLikeAccountStatement(_ text: String) -> Bool {
        let l = text.lowercased()
        var signals = 0
        if l.contains("voucher")            { signals += 1 }
        if l.contains("visit total")        { signals += 1 }
        if l.contains("insurance pending")  { signals += 1 }
        if l.contains("patient amount")     { signals += 1 }
        if l.contains("icpt")               { signals += 1 }
        if l.contains("charges") && (l.contains("credits") || l.contains("debits")) { signals += 1 }
        return signals >= 2
    }

    private func parseLineItems() {
        // Route to template-specific parser when available
        if let layout = detectedTemplate?.procedureColumnLayout,
           detectedTemplate?.billFormat == .accountStatement {
            parseAccountStatementLineItems(layout: layout)
            return
        }

        // Format-based fallback: recognize the account-statement layout from the
        // procedure text itself, even without a provider-template match.
        if looksLikeAccountStatement(procedureText) {
            var layout = ProcedureColumnLayout()
            layout.accountingRowKeywords += [
                "cigna", "aetna", "humana", "bcbs", "blue cross", "united health",
                "unitedhealth", "anthem", "medicare", "medicaid", "tricare",
                "self pay", "master card", "mastercard", "visa", "discover"
            ]
            parseAccountStatementLineItems(layout: layout)
            return
        }

        let lines = procedureText.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        
        var items: [ParsedLineItem] = []
        
        for line in lines {
            let lower = line.lowercased()
            
            // ── Skip header/label lines ──
            if lower.hasPrefix("date") && (lower.contains("code") || lower.contains("description") || lower.contains("cpt")
                || lower.contains("icpt") || lower.contains("reason") || lower.contains("activity")) { continue }
            if lower.hasPrefix("emergency department") || lower.hasPrefix("charges") { continue }
            // Column sub-headers
            if lower.contains("debits") && lower.contains("credits") { continue }
            if lower.contains("pending") && lower.contains("amount") && lower.contains("insurance") { continue }
            
            // ── Skip insurance transaction lines ──
            // These are payment/adjustment records, not procedures
            let insurancePatterns = [
                "payment", "adjustment", "transfer", "refund", "credit card",
                "self pay", "master card", "mastercard", "visa pay", "check pay",
                "write off", "write-off", "collection", "courtesy"
            ]
            if insurancePatterns.contains(where: { lower.contains($0) }) {
                // But capture negative amounts as insurance payments for running totals
                continue
            }
            
            // ── Skip voucher/visit total lines ──
            // BUT keep a row where OCR merged the "Voucher:" header onto an actual
            // procedure line (it still has a 5-digit CPT + charge), e.g.
            // "Voucher:  07/11/11  99214  2607480  Office/outpatient Visit  131.00  0.00"
            let hasCPTCode = line.range(of: #"\b\d{5}\b"#, options: .regularExpression) != nil
            if (lower.hasPrefix("voucher") && !hasCPTCode)
                || lower.contains("visit total") || lower.contains("---- ") { continue }
            // Skip "Patient:" label lines inside procedure area
            if lower.hasPrefix("patient:") { continue }
            
            // ── Extract financial summary from total/summary lines ──
            // IMPORTANT: check for specific financial labels BEFORE a generic "total" check.
            // A broad lower.contains("total") matches procedure descriptions like
            // "Total Knee Arthroplasty" (code 27447) and routes them to the summary parser,
            // silently dropping $22,500 from the line-items total.
            // Only treat a line as a summary line when:
            //  • it starts with the label (not mid-description), OR
            //  • it contains a recognised financial summary keyword pair
            let isFinancialSummaryLine =
                lower.hasPrefix("total charge") || lower.hasPrefix("subtotal") ||
                lower.hasPrefix("insurance adjust") || lower.hasPrefix("insurance paid") ||
                lower.hasPrefix("ins paid") || lower.hasPrefix("amount due") ||
                lower.hasPrefix("balance due") || lower.hasPrefix("you owe") ||
                lower.hasPrefix("patient resp") ||
                lower.contains("total charges") || lower.contains("total charge:") ||
                lower.contains("insurance adjustment") || lower.contains("insurance paid") ||
                lower.contains("amount due") || lower.contains("balance due") ||
                lower.contains("you owe") || lower.contains("patient responsibility") ||
                // Also catch "---- Total Charges" style labels
                (lower.contains("total") && (lower.contains("charge") || lower.contains("balance") || lower.contains("amount")))

            if isFinancialSummaryLine {
                let amt = extractStrictDollarAmount(from: line) ?? extractPlainAmount(from: line)
                if let amt = amt {
                    if lower.contains("total charge") || lower.contains("subtotal") {
                        totalCharges = String(format: "%.2f", amt)
                        if billedAmount.isEmpty { billedAmount = totalCharges }
                    } else if lower.contains("insurance adjust") || lower.contains("contractual") || lower.contains("write off") || lower.contains("write-off") {
                        insuranceAdjustment = String(format: "%.2f", amt)
                    } else if lower.contains("insurance paid") || lower.contains("ins paid") || lower.contains("ins payment") {
                        insurancePaid = String(format: "%.2f", amt)
                    } else if lower.contains("amount due") || lower.contains("balance due") || lower.contains("you owe") || lower.contains("patient resp") {
                        amountDue = String(format: "%.2f", amt)
                    }
                }
                continue
            }
            
            // Extract dollar amount — try "$" first, then plain decimal fallback
            var amount = extractStrictDollarAmount(from: line)
            if amount == nil {
                amount = extractPlainAmount(from: line)
            }
            
            // Skip statement header / contact rows misread as procedures, e.g.
            // "1  10/24/11  11/08/11  (386) 943-7100  38142  52.74"
            // (Page / Statement Date / Due Date / Phone / Account # / Balance).
            let phonePattern = #"\(?\d{3}\)?[-.\s]?\d{3}[-.\s]\d{4}"#
            if line.range(of: phonePattern, options: .regularExpression) != nil
                || lower.contains("account #") || lower.contains("account number")
                || lower.contains("patient balance") || lower.contains("statement date")
                || lower.contains("due date") || lower.contains("office phone") {
                continue
            }

            // Extract procedure code from the line
            let code = extractProcedureCode(from: line)

            // Must have at least an amount or a code to be a valid line item
            guard amount != nil || code != nil else { continue }
            
            // Build description by stripping code, amount, and date from line
            var desc = line
            
            // Remove the code
            if let code = code, let range = desc.range(of: code) {
                desc = String(desc[range.upperBound...])
            }
            
            // Remove dollar amounts (with $ sign)
            let dollarPattern = #"-?\$[\d,]+\.?\d{0,2}"#
            if let regex = try? NSRegularExpression(pattern: dollarPattern) {
                desc = regex.stringByReplacingMatches(in: desc, range: NSRange(desc.startIndex..., in: desc), withTemplate: "")
            }
            
            // Remove plain negative amounts like -51.55 (insurance payments in same row)
            let negAmtPattern = #"-\d+\.\d{2}"#
            if let regex = try? NSRegularExpression(pattern: negAmtPattern) {
                desc = regex.stringByReplacingMatches(in: desc, range: NSRange(desc.startIndex..., in: desc), withTemplate: "")
            }
            
            // Remove plain 0.00 amounts
            let zeroPattern = #"\b0\.00\b"#
            if let regex = try? NSRegularExpression(pattern: zeroPattern) {
                desc = regex.stringByReplacingMatches(in: desc, range: NSRange(desc.startIndex..., in: desc), withTemplate: "")
            }
            
            // Remove dates (MM/DD/YY or MM/DD/YYYY or MMDDYYYY)
            let datePattern = #"\d{1,2}/\d{1,2}/\d{2,4}"#
            if let regex = try? NSRegularExpression(pattern: datePattern) {
                desc = regex.stringByReplacingMatches(in: desc, range: NSRange(desc.startIndex..., in: desc), withTemplate: "")
            }
            let datePattern2 = #"\b\d{8}\b"#  // 07132011 format dates
            if let regex = try? NSRegularExpression(pattern: datePattern2) {
                desc = regex.stringByReplacingMatches(in: desc, range: NSRange(desc.startIndex..., in: desc), withTemplate: "")
            }

            // Remove standalone 6+ digit voucher / account numbers (e.g. 2607480)
            let longNumPattern = #"\b\d{6,}\b"#
            if let regex = try? NSRegularExpression(pattern: longNumPattern) {
                desc = regex.stringByReplacingMatches(in: desc, range: NSRange(desc.startIndex..., in: desc), withTemplate: "")
            }

            // Remove standalone single digits (quantity column)
            let qtyPattern = #"\b[1-9]\b"#
            if let regex = try? NSRegularExpression(pattern: qtyPattern) {
                desc = regex.stringByReplacingMatches(in: desc, range: NSRange(desc.startIndex..., in: desc), withTemplate: "")
            }
            
            desc = desc.trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "- ,"))
                .trimmingCharacters(in: .whitespaces)
            
            // Skip if we only got a code with no amount (likely a header fragment)
            if amount == nil && desc.isEmpty { continue }

            let newCode = code ?? ""
            // Dedup: the same code + amount appearing twice is an OCR/accumulation
            // artifact (e.g. the table captured twice), not two real charges.
            if !newCode.isEmpty,
               items.contains(where: { $0.code == newCode && abs($0.amount - (amount ?? 0)) < 0.01 }) {
                continue
            }

            items.append(ParsedLineItem(
                code: newCode,
                description: desc.isEmpty ? (code != nil ? "Procedure \(code!)" : "Unknown") : desc,
                amount: amount ?? 0
            ))
        }

        lineItems = items
    }
    
    // MARK: - Code Classification & Database Lookup
    
    /// Classify a code string into its medical code type using ScannerViewModel patterns
    private func classifyCodeType(_ code: String) -> MedicalCodeType? {
        let upper = code.uppercased()
        guard !upper.isEmpty else { return nil }
        
        let first = upper.first!
        
        // HCPCS: letter A-V + 4 digits
        if first.isLetter && first >= "A" && first <= "V" && upper.count == 5 {
            let digits = upper.dropFirst()
            if digits.allSatisfy(\.isNumber) { return .hcpcs }
        }
        
        // ICD-10-CM: letter + 2 digits + optional dot + 1-4 alphanumeric
        if first.isLetter && first != "U" && upper.count >= 3 {
            let afterFirst = upper.dropFirst()
            if afterFirst.prefix(2).allSatisfy(\.isNumber) {
                if upper.contains(".") || upper.count <= 7 {
                    return .icd10
                }
            }
        }
        
        // ICD-10-PCS: 7 alphanumeric
        if upper.count == 7 && upper.allSatisfy({ $0.isNumber || $0.isLetter }) {
            return .icd10pcs
        }
        
        // CPT: 5 digits in valid range
        if upper.count == 5 && upper.allSatisfy(\.isNumber) {
            if let num = Int(upper), num >= 10000 && num <= 99499 {
                return .cpt
            }
        }
        
        return nil
    }

    // MARK: - OCR Correction Helpers

    /// Common OCR character confusions for billing codes (digits + look-alike letters).
    private static let ocrCodeConfusions: [Character: [Character]] = [
        "0": ["O", "8", "6", "9", "D"], "1": ["7", "I", "L"], "2": ["7", "Z"],
        "3": ["8", "9"], "4": ["9"], "5": ["6", "8", "S"], "6": ["5", "8", "0", "G"],
        "7": ["1", "2"], "8": ["9", "0", "6", "3", "B", "5"], "9": ["8", "4", "0", "3"],
        "O": ["0"], "I": ["1"], "L": ["1"], "S": ["5"], "B": ["8"], "Z": ["2"], "G": ["6"]
    ]

    /// Generates candidate code spellings by applying one OCR-confusion swap at each
    /// position — used to recover a misread code (e.g. "98223" → "99223").
    private func ocrCodeVariants(_ code: String) -> [String] {
        let chars = Array(code.uppercased())
        var out: [String] = []
        for i in chars.indices {
            guard let subs = Self.ocrCodeConfusions[chars[i]] else { continue }
            for s in subs {
                var v = chars; v[i] = s; out.append(String(v))
            }
        }
        var seen = Set<String>([code.uppercased()])
        return out.filter { seen.insert($0).inserted }
    }

    /// Looks up a code in the database, trying OCR-confusion variants if the direct
    /// match fails. Returns the (possibly corrected) code and the matched record.
    private func databaseMatch(forCode code: String, ocrDescription: String) -> (code: String, match: MedicalCode)? {
        let upper = code.uppercased()
        if let direct = lookup(upper) { return (upper, direct) }

        // The code as read wasn't in the database. Try OCR-confusion variants — but ONLY
        // accept one whose canonical description CORROBORATES the OCR text. Otherwise a
        // correctly-read code that is merely missing from the (incomplete) database gets
        // morphed into a different, similar-looking code that happens to be present
        // (e.g. 99233 "Subsequent Hospital Care" → 99283 "Emergency dept visit"). Only a
        // genuine misread like 98223 → 99223 has a matching description, so gate on that.
        let desc = ocrDescription.trimmingCharacters(in: .whitespaces)
        guard !desc.isEmpty else { return nil }
        for variant in ocrCodeVariants(upper) {
            guard variant.count == upper.count, classifyCodeType(variant) != nil,
                  let m = lookup(variant) else { continue }
            if descriptionSimilarity(desc, m.shortDescription) >= 0.78 {
                return (variant, m)
            }
        }
        return nil
    }

    /// Lightweight normalized Levenshtein similarity in 0...1 (alphanumerics only).
    private func descriptionSimilarity(_ a: String, _ b: String) -> Double {
        func norm(_ s: String) -> [Character] {
            Array(s.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
                .map(Character.init))
        }
        let x = norm(a), y = norm(b)
        if x.isEmpty || y.isEmpty { return 0 }
        if x == y { return 1 }
        var prev = Array(0...y.count)
        var cur = [Int](repeating: 0, count: y.count + 1)
        for i in 1...x.count {
            cur[0] = i
            for j in 1...y.count {
                let cost = x[i - 1] == y[j - 1] ? 0 : 1
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
            }
            swap(&prev, &cur)
        }
        return 1.0 - Double(prev[y.count]) / Double(max(x.count, y.count))
    }

    /// Chooses the best description for a matched code: prefer the canonical DB
    /// description when the OCR text is empty/generic or is clearly the same
    /// description with OCR noise; otherwise keep the (often more specific) OCR text.
    private func reconcileDescription(ocr: String, canonical: String) -> String {
        let trimmed = ocr.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed.hasPrefix("Procedure ") || trimmed == "Unknown" { return canonical }
        if descriptionSimilarity(trimmed, canonical) >= 0.70 { return canonical }
        return trimmed
    }

    /// Valid US state / territory codes, for address state-abbreviation correction.
    private static let usStateCodes: Set<String> = [
        "AL","AK","AZ","AR","CA","CO","CT","DE","FL","GA","HI","ID","IL","IN","IA",
        "KS","KY","LA","ME","MD","MA","MI","MN","MS","MO","MT","NE","NV","NH","NJ",
        "NM","NY","NC","ND","OH","OK","OR","PA","RI","SC","SD","TN","TX","UT","VT",
        "VA","WA","WV","WI","WY","DC","PR","VI","GU"
    ]

    private static let ocrLetterConfusions: [Character: [Character]] = [
        "R": ["L","P","K","B"], "L": ["R","I","E"], "I": ["L","T"],
        "O": ["Q","D","C"], "B": ["R","E"], "G": ["C"], "C": ["G","O"],
        "D": ["O"], "U": ["V"], "V": ["U","Y"], "N": ["M","H"], "M": ["N"],
        "E": ["F","B"], "F": ["E","P"], "P": ["F","R"], "T": ["I","Y"],
        "Y": ["V","T"], "K": ["R","X"], "S": ["B"], "Q": ["O"]
    ]

    private func ocrLetterVariants(_ token: String) -> [String] {
        let chars = Array(token.uppercased())
        var out: [String] = []
        for i in chars.indices {
            guard let subs = Self.ocrLetterConfusions[chars[i]] else { continue }
            for s in subs where s.isLetter {
                var v = chars; v[i] = s; out.append(String(v))
            }
        }
        var seen = Set<String>([token.uppercased()])
        return out.filter { seen.insert($0).inserted }
    }

    /// Fixes a misread 2-letter state code that precedes a ZIP, e.g.
    /// "Orlando, FR 32806" → "Orlando, FL 32806" (OCR L→R).
    private func correctStateCode(in address: String) -> String {
        let pattern = #"\b([A-Za-z]{2})\s+(\d{5}(?:-\d{4})?)\b"#
        guard let re = try? NSRegularExpression(pattern: pattern) else { return address }
        let ns = address as NSString
        guard let m = re.firstMatch(in: address, range: NSRange(location: 0, length: ns.length)) else { return address }
        let stateRange = m.range(at: 1)
        let state = ns.substring(with: stateRange).uppercased()
        if Self.usStateCodes.contains(state) { return address }
        for variant in ocrLetterVariants(state) where Self.usStateCodes.contains(variant) {
            return ns.replacingCharacters(in: stateRange, with: variant)
        }
        return address
    }

    // MARK: - Account Statement Line Item Parser (multi-column format)

    /// Parses procedure line items from an account-statement bill (e.g. West Volusia).
    ///
    /// Account statement format groups charges by visit/voucher.  Each voucher contains:
    ///  - Procedure rows: date + code + description + charge amount
    ///  - Accounting rows: insurance payments, adjustments, patient payments
    ///  - A "Visit Total" row with the net patient responsibility
    ///
    /// This parser:
    ///  1. Skips accounting/payment rows (using `layout.accountingRowKeywords`)
    ///  2. Extracts CPT-coded procedure rows with their charge amounts
    ///  3. Sums Visit Total lines to compute total patient responsibility
    ///  4. Falls back to "Patient Balance:" at the bottom of the statement
    private func parseAccountStatementLineItems(layout: ProcedureColumnLayout) {
        let lines = procedureText.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var items: [ParsedLineItem] = []
        var visitTotalSum: Double = 0

        // Money tokens REQUIRE decimals, so dates ("07/11/11") and codes/vouchers are
        // never mistaken for a charge (this is what caused the bogus $7.00 / $10.00 —
        // the old "first number" grabbed "07" from the date). Preserves sign.
        func moneyValues(in line: String) -> [Double] {
            let pattern = #"-?\$?\s*\d{1,3}(?:,\d{3})*\.\d{2}\b"#
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
            let ns = line as NSString
            return regex.matches(in: line, range: NSRange(location: 0, length: ns.length)).compactMap {
                let raw = ns.substring(with: $0.range)
                guard let v = normalizeAmountToken(raw) else { return nil }
                return raw.contains("-") ? -abs(v) : v
            }
        }

        // First valid CPT (5-digit in range) or HCPCS code on a line.
        func firstCPT(in line: String) -> String? {
            if let r = line.range(of: #"\b\d{5}\b"#, options: .regularExpression) {
                let c = String(line[r])
                if let n = Int(c), n >= 10000 && n <= 99499 { return c }
            }
            if let r = line.range(of: #"\b[A-Z]\d{4}\b"#, options: .regularExpression) {
                return String(line[r])
            }
            return nil
        }

        // Human-readable label for a payment/credit row from the keywords present.
        func paymentLabel(from line: String) -> String {
            let l = line.lowercased()
            if l.contains("adjustment") || l.contains("contractual") || l.contains("write off") || l.contains("write-off") {
                return "Insurance Adjustment"
            }
            if l.contains("transfer")            { return "Transfer" }
            if l.contains("self pay") || l.contains("master card") || l.contains("credit card") || l.contains("mastercard") || l.contains("visa") {
                return "Self-Pay / Card Payment"
            }
            if l.contains("refund")              { return "Refund" }
            if l.contains("payment")             { return "Insurance Payment" }
            return "Payment / Credit"
        }

        for line in lines {
            let lower = line.lowercased()

            // ── Skip headers / patient / contact rows ──
            if lower.hasPrefix("date") && (lower.contains("code") || lower.contains("reason")
                || lower.contains("activity") || lower.contains("description")) { continue }
            if lower.hasPrefix("patient:") { continue }
            // Statement header/contact row (carries the office phone + account #)
            if line.range(of: #"\(?\d{3}\)?[-.\s]?\d{3}[-.\s]\d{4}"#, options: .regularExpression) != nil { continue }

            // ── Skip footer / instruction junk ──
            if lower.contains("return this portion") || lower.contains("reverse side")
                || lower.contains("indicate address") || lower.contains("show amount") { continue }

            // ── Explicit summary labels ──
            if lower.contains("total charge") || lower.contains("charges total") {
                if let amt = moneyValues(in: line).max() {
                    totalCharges = String(format: "%.2f", amt)
                    if billedAmount.isEmpty { billedAmount = totalCharges }
                }
                continue
            }
            if lower.contains("insurance paid") || lower.contains("ins paid") {
                if let amt = moneyValues(in: line).first(where: { $0 != 0 }) {
                    insurancePaid = String(format: "%.2f", abs(amt))
                }
                continue
            }
            if lower.contains("patient balance") || lower.contains("amount due") || lower.contains("balance due") {
                if let amt = moneyValues(in: line).last(where: { $0 > 0 }) {
                    amountDue = String(format: "%.2f", amt)
                }
                continue
            }

            let money = moneyValues(in: line)

            // ── CPT row → CHARGE (first positive money = Charges & Debits column) ──
            if let cpt = firstCPT(in: line) {
                let charge = money.first(where: { $0 > 0 }) ?? 0
                let description = extractStatementDescription(from: line, code: cpt)
                items.append(ParsedLineItem(code: cpt, description: description,
                                            amount: charge, codeType: classifyCodeType(cpt)))
                // Any negative merged onto this row is a credit.
                for c in money.filter({ $0 < 0 }) {
                    items.append(ParsedLineItem(code: "", description: paymentLabel(from: line),
                                                amount: c, isSelected: false, kind: .payment))
                }
                continue
            }

            // ── A NEGATIVE amount anywhere is a credit/payment — regardless of which
            //    line OCR scattered it onto (incl. ones misplaced onto a Visit Total
            //    row). This is robust to the heavy column-merging in these statements. ──
            let negatives = money.filter { $0 < 0 }
            if !negatives.isEmpty {
                let label = paymentLabel(from: line)
                for n in negatives {
                    items.append(ParsedLineItem(code: "", description: label,
                                                amount: n, isSelected: false, kind: .payment))
                }
                continue
            }

            // ── A genuine (positive) Visit Total = patient responsibility ──
            if lower.contains("visit total") {
                if let amt = money.last(where: { $0 > 0 }) { visitTotalSum += amt }
                continue
            }
        }

        lineItems = items

        let chargesSum = items.filter { $0.kind == .charge }.reduce(0) { $0 + $1.amount }
        let creditsSum = items.filter { $0.kind == .payment }.reduce(0) { $0 + $1.amount }

        if amountDue.isEmpty {
            if visitTotalSum > 0 {
                amountDue = String(format: "%.2f", visitTotalSum)
            } else {
                // Patient owes charges minus credits (credits are stored negative).
                let bal = chargesSum + creditsSum
                if bal >= 0 { amountDue = String(format: "%.2f", bal) }
            }
        }
        if billedAmount.isEmpty {
            billedAmount = !totalCharges.isEmpty ? totalCharges
                : (chargesSum > 0 ? String(format: "%.2f", chargesSum) : amountDue)
        }

        #if DEBUG
        let c = items.filter { $0.kind == .charge }.count
        let p = items.filter { $0.kind == .payment }.count
        print("── AccountStatement: \(c) charges, \(p) credits, chargesSum=\(chargesSum), creditsSum=\(creditsSum), amountDue=\(amountDue)")
        #endif
    }

    /// Returns the first dollar-formatted amount found on a line.
    /// Used to extract the "Charges & Debits" column (leftmost dollar value).
    private func extractFirstDollarAmount(from text: String) -> Double? {
        let pattern = #"\$?\s*([0-9][0-9.,]*)"#
        guard let match = text.range(of: pattern, options: .regularExpression) else { return nil }
        return normalizeAmountToken(String(text[match]))
    }

    /// Returns the LAST dollar-formatted amount found on a line.
    /// Used to extract the "Patient Amount" column (rightmost dollar value).
    private func extractLastDollarAmount(from text: String) -> Double? {
        let pattern = #"\$?\s*([0-9][0-9.,]*)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: range)
        guard let last = matches.last,
              let r = Range(last.range(at: 1), in: text) else { return nil }
        return normalizeAmountToken(String(text[r]))
    }

    /// Extracts the first 5-digit CPT code or HCPCS code from a statement line.
    private func extractFirstMedicalCode(from line: String) -> String {
        // 5-digit CPT: 10000–99499
        if let range = line.range(of: #"\b[0-9]{5}\b"#, options: .regularExpression) {
            let candidate = String(line[range])
            if let n = Int(candidate), n >= 10000 && n <= 99499 { return candidate }
        }
        // HCPCS: letter + 4 digits (e.g. J2175)
        if let range = line.range(of: #"\b[A-Z][0-9]{4}\b"#, options: .regularExpression) {
            return String(line[range])
        }
        return ""
    }

    /// Extracts the description portion of a statement line (between the code and first dollar).
    private func extractStatementDescription(from line: String, code: String) -> String {
        var work = line
        // Remove leading date
        if let dateEnd = work.range(of: #"^\d{1,2}[/\-]\d{1,2}[/\-]\d{2,4}\s*"#, options: .regularExpression) {
            work = String(work[dateEnd.upperBound...])
        }
        // Remove the code if present
        if !code.isEmpty, let codeRange = work.range(of: code) {
            work = String(work[codeRange.upperBound...]).trimmingCharacters(in: .whitespaces)
        }
        // Take everything up to the first dollar amount or digit sequence that looks like a column value
        if let amtRange = work.range(of: #"\s+\$?[\d,]+\.?\d{0,2}"#, options: .regularExpression) {
            work = String(work[work.startIndex..<amtRange.lowerBound])
        }
        return work.trimmingCharacters(in: .whitespaces)
    }

    /// Look up each line item's code in the medical code database
    private func lookupLineItemCodes() {
        
        for i in lineItems.indices {
            guard lineItems[i].kind == .charge else { continue }   // payments/credits carry no code
            let code = lineItems[i].code
            guard !code.isEmpty else { continue }

            // Classify the code type
            lineItems[i].codeType = classifyCodeType(code)

            // Look up in the database — tries OCR-confusion variants if the
            // direct match fails (e.g. "98223" → "99223").
            if let result = databaseMatch(forCode: code, ocrDescription: lineItems[i].description) {
                if result.code != code.uppercased() {
                    lineItems[i].code = result.code   // adopt the OCR-corrected code
                    #if DEBUG
                    print("  ✏️ OCR-corrected code \(code) → \(result.code)")
                    #endif
                }
                lineItems[i].matchedMedicalCode = result.match
                lineItems[i].codeType = result.match.codeType
                lineItems[i].lookupFailed = false

                // Prefer the canonical description when OCR is empty/generic or is
                // the same description with OCR noise ("Inital" → "Initial"); keep
                // a more-specific OCR description otherwise.
                lineItems[i].description = reconcileDescription(
                    ocr: lineItems[i].description,
                    canonical: result.match.shortDescription
                )

                #if DEBUG
                print("  🔍 \(result.code) → \(result.match.shortDescription) [\(result.match.codeType.rawValue)]")
                #endif
            } else {
                lineItems[i].lookupFailed = true
                #if DEBUG
                print("  🔍 \(code) → not found in database")
                #endif
            }
        }
        
        // Also scan the full procedure text for additional codes not captured as line items
        scanForAdditionalCodes()
    }
    
    /// Scan procedure + insurance text for medical codes that weren't captured as line items
    private func scanForAdditionalCodes() {
        let allText = (procedureText + "\n" + insuranceText).uppercased()
        let existingCodes = Set(lineItems.map { $0.code.uppercased() })
        
        // Regex patterns from ScannerViewModel
        let patterns: [(String, MedicalCodeType)] = [
            (#"\b([A-V]\d{4})\b"#, .hcpcs),
            (#"\b(\d{5})\b"#, .cpt),
            (#"\b([A-TV-Z]\d{2}(?:\.\d{1,4})?)\b"#, .icd10)
        ]
        
        var newItems: [ParsedLineItem] = []
        
        for (pattern, codeType) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let matches = regex.matches(in: allText, range: NSRange(allText.startIndex..., in: allText))
            
            for match in matches {
                guard let range = Range(match.range(at: 1), in: allText) else { continue }
                let code = String(allText[range])
                
                // Skip if already a line item or invalid
                guard !existingCodes.contains(code) else { continue }
                guard classifyCodeType(code) != nil else { continue }
                
                // For CPT, reject if < 10000
                if codeType == .cpt, let num = Int(code), num < 10000 { continue }

                // Context-aware false-positive rejection for 5-digit "CPT" matches:
                // ZIP codes (FL 32720 / 32720-0824) and account/voucher numbers are
                // 5 digits too and otherwise get mistaken for procedure codes.
                if codeType == .cpt {
                    let ns = allText as NSString
                    let loc = match.range(at: 1).location
                    let len = match.range(at: 1).length
                    let preStart = max(0, loc - 28)
                    let pre = ns.substring(with: NSRange(location: preStart, length: loc - preStart))
                    let postLen = min(6, ns.length - (loc + len))
                    let post = ns.substring(with: NSRange(location: loc + len, length: postLen))
                    // ZIP+4 (e.g. 32720-0824)
                    if post.range(of: #"^-\d{4}"#, options: .regularExpression) != nil { continue }
                    // ZIP preceded by a 2-letter US state abbreviation (…DELAND FL 32720)
                    let preTrim = pre.trimmingCharacters(in: .whitespaces)
                    if preTrim.count >= 2, Self.usStateCodes.contains(String(preTrim.suffix(2))) { continue }
                    // Account / voucher / balance / statement / phone context
                    if ["ACCOUNT", "ACCT", "VOUCHER", "BALANCE", "ZIP", "PHONE",
                        "STATEMENT", "PAGE", "PORTION", "#"]
                        .contains(where: { pre.contains($0) }) { continue }
                    // Account number sitting right after a phone number (…943-7100  STATEMENT  38142)
                    if pre.range(of: #"\d{3}[-.\s]\d{4}"#, options: .regularExpression) != nil { continue }
                }

                // Avoid duplicates in new items
                guard !newItems.contains(where: { $0.code == code }) else { continue }
                
                // Look up in database
                let matched = lookup(code)
                let desc = matched?.shortDescription ?? "Detected \(codeType.rawValue) code"
                
                let item = ParsedLineItem(
                    code: code,
                    description: desc,
                    amount: 0,
                    isSelected: false,  // Not auto-selected — user decides
                    codeType: codeType,
                    matchedMedicalCode: matched,
                    lookupFailed: matched == nil
                )
                
                newItems.append(item)
                
                #if DEBUG
                print("  🆕 Additional code: \(code) → \(desc)")
                #endif
            }
        }
        
        if !newItems.isEmpty {
            lineItems.append(contentsOf: newItems)
        }
    }
    
    
    // MARK: - Parsing Helpers
    
    /// Known labels for multi-label splitting — ordered longest first to avoid partial matches
    private static let knownLabels: [(pattern: String, key: String)] = [
        ("patient name", "patient name"), ("patient address", "patient address"),
        ("patient", "patient"), ("name", "name"),
        ("insured name", "insured name"), ("insured", "insured"),
        ("subscriber", "subscriber"),
        ("account number", "account number"), ("account #", "account #"),
        ("account no", "account no"), ("acct #", "acct #"), ("account", "account"),
        ("date of service", "date of service"), ("date(s) of service", "date of service"),
        ("service date", "service date"), ("dos", "dos"),
        ("date of birth", "date of birth"), ("dob", "dob"),
        ("mrn", "mrn"), ("medical record number", "mrn"), ("medical record", "mrn"),
        ("discharge date", "discharge date"), ("discharged", "discharge date"),
        ("date of discharge", "discharge date"), ("disch date", "discharge date"),
        ("admit date", "admit date"), ("admission date", "admit date"),
        ("date of admission", "admit date"), ("admitted", "admit date"),
        ("insurance company", "insurance company"), ("insurance", "insurance"),
        ("carrier", "carrier"), ("payer", "payer"),
        ("policy number", "policy number"), ("policy #", "policy #"),
        ("policy no", "policy no"), ("policy", "policy"),
        ("member id", "member id"), ("member #", "member #"), ("member", "member"),
        ("subscriber id", "subscriber id"), ("id #", "id #"),
        ("group number", "group number"), ("group #", "group #"),
        ("group no", "group no"), ("group", "group"),
        ("plan type", "plan type"), ("plan name", "plan name"),
        ("provider", "provider"), ("facility", "facility"),
        ("hospital", "hospital"), ("clinic", "clinic"),
        ("remit to", "remit to"), ("pay to", "remit to"), ("send to", "remit to"),
        ("return to", "remit to"), ("bill to", "remit to"),
        ("office phone number", "office phone"), ("office phone", "office phone"),
        ("phone number", "phone"), ("phone", "phone"), ("tel", "tel"), ("telephone", "telephone"),
        ("fax", "fax"), ("npi", "npi"), ("address", "address"),
        ("voucher", "voucher"),
        ("statement date", "statement date"), ("due date", "due date"),
        ("patient balance", "patient balance"),
        ("email", "email"), ("e-mail", "email"),
        ("website", "website"), ("web", "website"), ("url", "website"),
        ("tax id", "tax id"), ("tax identification", "tax id"), ("ein", "ein"),
        ("federal id", "tax id"), ("fed id", "tax id"),
        ("license number", "license"), ("license #", "license"),
        ("license no", "license"), ("lic #", "license"), ("lic", "license"),
        ("total charges", "total charges"), ("amount due", "amount due"),
        ("insurance paid", "insurance paid"), ("insurance adjustment", "insurance adjustment"),
    ]
    
    /// Extract ALL label:value pairs from lines, splitting multi-label lines
    /// e.g. "Patient: Michael R. Thompson  Account #: ACCT-2024-78452"
    /// → [("patient", "Michael R. Thompson"), ("account #", "ACCT-2024-78452")]
    private func extractAllLabelValuePairs(from lines: [String]) -> [(String, String)] {
        var pairs: [(String, String)] = []
        
        for line in lines {
            let lower = line.lowercased()
            
            // Find all recognized label positions in this line
            var labelPositions: [(pos: Int, len: Int, key: String)] = []
            
            for (pattern, key) in Self.knownLabels {
                var searchStart = lower.startIndex
                while let range = lower.range(of: pattern, range: searchStart..<lower.endIndex) {
                    // Check that a colon follows (possibly with whitespace)
                    let afterLabel = lower[range.upperBound...].trimmingCharacters(in: .whitespaces)
                    guard afterLabel.hasPrefix(":") || lower[range.upperBound...].hasPrefix(":") else {
                        searchStart = range.upperBound; continue
                    }
                    
                    let pos = lower.distance(from: lower.startIndex, to: range.lowerBound)
                    // Find the colon position
                    let colonSearchStart = range.upperBound
                    guard let colonRange = lower.range(of: ":", range: colonSearchStart..<lower.endIndex) else {
                        searchStart = range.upperBound; continue
                    }
                    let colonPos = lower.distance(from: lower.startIndex, to: colonRange.upperBound)
                    let len = colonPos - pos
                    
                    // Don't add if overlaps with a longer label at same position
                    if !labelPositions.contains(where: { $0.pos == pos && $0.len >= len }) {
                        labelPositions.removeAll { $0.pos == pos && $0.len < len }
                        labelPositions.append((pos, len, key))
                    }
                    searchStart = colonRange.upperBound
                }
            }
            
            if labelPositions.isEmpty {
                // No recognized labels — try generic "Word: Value" pattern
                if let colonRange = line.range(of: ":") {
                    let label = String(line[line.startIndex..<colonRange.lowerBound]).trimmingCharacters(in: .whitespaces)
                    let value = String(line[colonRange.upperBound...]).trimmingCharacters(in: .whitespaces)
                    if !label.isEmpty && label.count <= 30 && !value.isEmpty {
                        pairs.append((label, value))
                    }
                }
                continue
            }
            
            // Sort by position and extract values
            labelPositions.sort { $0.pos < $1.pos }

            let lineCount = line.count
            for (idx, lp) in labelPositions.enumerated() {
                // Guard: valueStart must not exceed the line length
                let startOffset = min(lp.pos + lp.len, lineCount)
                let valueStart  = line.index(line.startIndex, offsetBy: startOffset)

                let valueEnd: String.Index
                if idx + 1 < labelPositions.count {
                    // Guard: valueEnd must not precede valueStart (overlapping labels)
                    let endOffset = min(
                        max(labelPositions[idx + 1].pos, startOffset),
                        lineCount
                    )
                    valueEnd = line.index(line.startIndex, offsetBy: endOffset)
                } else {
                    valueEnd = line.endIndex
                }

                // Final safety net — skip silently if range is somehow still inverted
                guard valueStart <= valueEnd else { continue }

                let value = String(line[valueStart..<valueEnd]).trimmingCharacters(in: .whitespaces)
                if !value.isEmpty {
                    pairs.append((lp.key, value))
                }
            }
        }
        
        return pairs
    }
    
    private func parseDate(_ text: String) -> Date? {
        let formatters = [
            "MM/dd/yyyy", "M/d/yyyy", "MM/dd/yy", "M/d/yy",
            "yyyy-MM-dd", "MM-dd-yyyy", "M-d-yy"
        ]
        for fmt in formatters {
            let df = DateFormatter()
            df.dateFormat = fmt
            df.locale = Locale(identifier: "en_US_POSIX")
            if let date = df.date(from: text.trimmingCharacters(in: .whitespaces)) {
                return date
            }
        }
        return nil
    }
    
    private func looksLikeName(_ text: String) -> Bool {
        let words = text.split(separator: " ")
        if words.count < 2 || words.count > 5 { return false }
        return text.rangeOfCharacter(from: .decimalDigits) == nil && words.allSatisfy { $0.first?.isLetter == true }
    }
    
    private func looksLikeAddress(_ text: String) -> Bool {
        let upper = text.uppercased()
        let indicators = ["STREET", "ST.", "ST ", "AVE", "AVENUE", "BLVD", "DRIVE", "DR.", "DR ",
                          "ROAD", "RD.", "RD ", "LANE", "LN.", "LN ", "WAY", "SUITE", "STE",
                          "P.O. BOX", "PO BOX", "P O BOX", "COURT", "CT.", "CT ",
                          "CIRCLE", "CIR", "PLACE", "PL.", "PIKE", "HWY", "HIGHWAY",
                          "NORTH ", "SOUTH ", "EAST ", "WEST ", " N ", " S ", " E ", " W "]
        if indicators.contains(where: { upper.contains($0) }) { return true }
        if text.first?.isNumber == true && text.count > 10 { return true }
        return text.range(of: #"\b\d{5}(-\d{4})?\b"#, options: .regularExpression) != nil
    }
    
    private func looksLikePhone(_ text: String) -> Bool {
        let digits = text.filter { $0.isNumber }
        return digits.count >= 10 && digits.count <= 11
    }

    /// True if a line looks like a file name or document-viewer window chrome
    /// (e.g. "12_Routine_Phys… 1 page", "Invoice_2024.pdf", "Scan — Preview")
    /// rather than a real provider/business name. Used to keep on-screen capture
    /// artifacts from being mistaken for the facility name.
    private func looksLikeFilename(_ raw: String) -> Bool {
        let s = raw.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return false }
        let lower = s.lowercased()

        // 1. A document/image/file extension anywhere in the line.
        let exts = [".pdf", ".png", ".jpg", ".jpeg", ".heic", ".heif", ".tiff", ".tif",
                    ".gif", ".bmp", ".webp", ".doc", ".docx", ".pages", ".numbers",
                    ".txt", ".rtf", ".key", ".ppt", ".pptx", ".xls", ".xlsx"]
        if exts.contains(where: { lower.contains($0) }) { return true }

        // 2. Viewer window chrome: "1 page", "2 of 5 pages", app names.
        if lower.range(of: #"\b\d+\s+of\s+\d+\s+pages?\b"#, options: .regularExpression) != nil { return true }
        if lower.range(of: #"\b\d+\s+pages?\b"#, options: .regularExpression) != nil { return true }
        let viewerWords = ["preview", "adobe", "acrobat", "quick look", "quicklook", "— pdf", "- pdf"]
        if viewerWords.contains(where: { lower.contains($0) }) { return true }

        // 3. Ellipsis-truncated title-bar token (e.g. "12_Routine_Phys…").
        if (s.contains("…") || s.hasSuffix("...")) && s.split(separator: " ").count <= 2 { return true }

        // 4. Underscore-joined filename tokens with little or no spacing.
        let spaceCount = s.filter { $0 == " " }.count
        let underscoreCount = s.filter { $0 == "_" }.count
        if underscoreCount >= 1 && spaceCount <= 1 { return true }

        return false
    }

    /// True if a line looks like a charges-table / procedure row rather than a
    /// facility name — e.g. "10/10/24  99223  Initial Hospital Care   $1,450.00".
    /// Critical because CPT descriptions like "Initial Hospital Care",
    /// "Subsequent Hospital Care", and "Hospital Discharge Day" all contain the
    /// facility keyword "HOSPITAL" and would otherwise be mistaken for the provider.
    private func looksLikeProcedureRow(_ raw: String) -> Bool {
        let s = raw.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return false }
        // Starts with a service date or date range: 10/10/24, 10/10/2024, 10/11-16
        if s.range(of: #"^\d{1,2}/\d{1,2}(/\d{2,4}|-\d{1,2})"#, options: .regularExpression) != nil { return true }
        // Contains a standalone 5-digit CPT code
        if s.range(of: #"\b\d{5}\b"#, options: .regularExpression) != nil { return true }
        // Contains a HCPCS code (letter + 4 digits, e.g. J2175)
        if s.range(of: #"\b[A-Z]\d{4}\b"#, options: .regularExpression) != nil { return true }
        // Contains a dollar amount (charge column)
        if s.range(of: #"\$\s?\d"#, options: .regularExpression) != nil { return true }
        return false
    }
    
    private func extractProcedureCode(from text: String) -> String? {
        // CPT codes: 5 digits (99284, 71046, etc.)
        // HCPCS codes: letter + 4 digits (J2175, etc.)
        // Revenue codes: 4 digits (0121, 0112, etc.) — hospital UB-04 billing
        // ICD-10: letter + 2-4 digits with optional dot (A01.1, M54.5)
        let patterns = [
            #"\b([A-Z]\d{4})\b"#,          // HCPCS: J2175
            #"\b(\d{5})\b"#,                // CPT: 99284
            #"\b(0\d{3})\b"#,               // Revenue code: 0121 (starts with 0, 4 digits)
            #"\b([A-Z]\d{2,4}\.?\d{0,2})\b"# // ICD-10: M54.5
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let range = Range(match.range(at: 1), in: text) {
                let code = String(text[range])
                
                // Reject if the code is part of a longer digit sequence (account #, date, etc.)
                if range.lowerBound > text.startIndex {
                    let before = text[text.index(before: range.lowerBound)]
                    if before.isNumber { continue }
                }
                if range.upperBound < text.endIndex {
                    let after = text[range.upperBound]
                    if after.isNumber { continue }
                }
                
                // Reject ZIP codes (5 digits preceded by state abbreviation)
                if code.allSatisfy(\.isNumber), code.count == 5 {
                    let beforeCode = String(text[text.startIndex..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
                    if beforeCode.count >= 2 {
                        let lastTwo = String(beforeCode.suffix(2)).uppercased()
                        let states: Set<String> = ["AL","AK","AZ","AR","CA","CO","CT","DE","FL","GA","HI","ID",
                                                   "IL","IN","IA","KS","KY","LA","ME","MD","MA","MI","MN","MS",
                                                   "MO","MT","NE","NV","NH","NJ","NM","NY","NC","ND","OH","OK",
                                                   "OR","PA","RI","SC","SD","TN","TX","UT","VT","VA","WA","WV","WI","WY"]
                        if states.contains(lastTwo) { continue }
                    }
                    
                    if let num = Int(code) {
                        if num < 10000 { continue }
                    }
                }
                
                return code
            }
        }
        return nil
    }
    
    /// Extract dollar amount — REQUIRES "$" sign to avoid matching dates (11/15/24 → 24)
    /// Parses a money token into a Double, tolerating OCR that misreads a thousands
    /// comma as a period (so "$22,500.00" arrives as "22.500.00"). Rule: unify "," and
    /// "." to a single separator; the LAST group is the decimal only if it has ≤2 digits,
    /// otherwise every separator is a thousands separator (no decimal).
    ///   "22,500.00" / "22.500.00" → 22500.00      "3.850.00" → 3850.00
    ///   "245.00" → 245.00          "1.500" → 1500   "22.50" → 22.50
    private func normalizeAmountToken(_ raw: String) -> Double? {
        var s = raw.replacingOccurrences(of: "$", with: "")
                   .replacingOccurrences(of: " ", with: "")
                   .trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return nil }
        let negative = s.hasPrefix("-")
        if negative { s.removeFirst() }
        s = s.replacingOccurrences(of: ",", with: ".")
        let parts = s.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else { return nil }

        let intPart: String
        let fracPart: String
        if parts.count == 1 {
            intPart = parts[0]; fracPart = ""
        } else if let last = parts.last, last.count <= 2 {
            fracPart = last; intPart = parts.dropLast().joined()
        } else {
            intPart = parts.joined(); fracPart = ""
        }
        let combined = fracPart.isEmpty ? intPart : "\(intPart).\(fracPart)"
        guard let val = Double(combined) else { return nil }
        return negative ? -val : val
    }

    private func extractStrictDollarAmount(from text: String) -> Double? {
        // "$" then a run of digits and grouping separators (commas, or OCR-misread
        // periods). normalizeAmountToken sorts out thousands vs decimal.
        let pattern = #"-?\$\s*([0-9][0-9.,]*)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)

        var amounts: [Double] = []
        for match in regex.matches(in: text, range: range) {
            if let r = Range(match.range(at: 1), in: text),
               let amount = normalizeAmountToken(String(text[r])), amount > 0 {
                amounts.append(amount)
            }
        }
        // Return the largest amount (most likely the charge, not quantity)
        return amounts.max()
    }
    
    /// Extract a plain decimal amount (no "$" required) — used as fallback
    /// Only matches numbers with exactly 2 decimal places to avoid matching dates, quantities, etc.
    private func extractPlainAmount(from text: String) -> Double? {
        // Match numbers like 15,000.00 or 245.00 — must have .XX decimal
        let pattern = #"\b(\d{1,3}(?:,\d{3})*\.\d{2})\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: range)
        
        var amounts: [Double] = []
        for match in matches {
            guard let r = Range(match.range(at: 1), in: text) else { continue }
            let numStr = String(text[r]).replacingOccurrences(of: ",", with: "")
            guard let val = Double(numStr), val > 0.99 else { continue }  // Skip tiny values (likely not charges)
            
            // Reject if it looks like a date (e.g., 10/15/2024 → "2024" won't match .XX pattern, but 10.15 could)
            // Check that there's no "/" immediately before or after
            if match.range.location > 0 {
                let nsText = text as NSString
                let charBefore = nsText.substring(with: NSRange(location: match.range.location - 1, length: 1))
                if charBefore == "/" { continue }
            }
            let endLoc = match.range.location + match.range.length
            if endLoc < (text as NSString).length {
                let charAfter = (text as NSString).substring(with: NSRange(location: endLoc, length: 1))
                if charAfter == "/" { continue }
            }
            
            amounts.append(val)
        }
        
        return amounts.max()
    }
    
    // MARK: - Scanned Name Parsing
    
    /// Split scanned patientName into first/last for Patient creation
    private var scannedFirstName: String {
        let parts = patientName.trimmingCharacters(in: .whitespaces).split(separator: " ")
        return parts.first.map(String.init) ?? ""
    }
    
    private var scannedLastName: String {
        let parts = patientName.trimmingCharacters(in: .whitespaces).split(separator: " ")
        if parts.count >= 2 {
            return parts.dropFirst().joined(separator: " ")
        }
        return ""
    }
}
