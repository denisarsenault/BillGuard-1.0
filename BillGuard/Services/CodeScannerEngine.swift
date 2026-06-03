//
//  CodeScannerEngine.swift
//  BillGuard
//
//  Shared column-aware OCR code detection engine.
//  Extracted from ScannerView to reuse in BillScannerView.
//

import Foundation
import Vision
import UIKit

// MARK: - Cell Classification

enum OCRCellKind { case code, amount, text }

// MARK: - Code Scanner Engine

/// Stateless engine for detecting medical codes from OCR cells.
/// Used by both ScannerView (Search Codes) and BillScannerView (Scan Bill).
struct CodeScannerEngine {
    
    // MARK: - OCR with Bounding Boxes
    
    /// Run Vision OCR and return individual text cells with positions
    static func recognizeWithPositions(_ image: UIImage, region: CGRect? = nil) async throws -> [OCRTextCell] {
        guard let cgFull = image.cgImage else {
            throw NSError(domain: "CodeScannerEngine", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid image"])
        }
        
        let cg: CGImage
        if let region = region {
            let imageRect = CGRect(x: 0, y: 0, width: cgFull.width, height: cgFull.height)
            let valid = region.intersection(imageRect)
            guard !valid.isEmpty, valid.width > 0, valid.height > 0,
                  let cropped = cgFull.cropping(to: valid) else {
                return []
            }
            cg = cropped
        } else {
            cg = cgFull
        }
        
        return try await withCheckedThrowingContinuation { cont in
            let req = VNRecognizeTextRequest { req, err in
                if let err { cont.resume(throwing: err); return }
                guard let obs = req.results as? [VNRecognizedTextObservation] else {
                    cont.resume(returning: []); return
                }
                let cells: [OCRTextCell] = obs.compactMap { o in
                    guard let c = o.topCandidates(1).first else { return nil }
                    let b = o.boundingBox
                    return OCRTextCell(text: c.string, midX: b.midX, midY: b.midY, width: b.width, height: b.height)
                }
                cont.resume(returning: cells)
            }
            req.recognitionLevel = .accurate
            req.usesLanguageCorrection = true
            let handler = VNImageRequestHandler(cgImage: cg, options: [:])
            do { try handler.perform([req]) }
            catch { cont.resume(throwing: error) }
        }
    }
    
    // MARK: - Cell Classification
    
    static func classifyCell(_ text: String) -> (OCRCellKind, String) {
        let t = text.trimmingCharacters(in: .whitespaces)
        let u = t.uppercased()
        
        // Dollar amount
        if t.range(of: #"^\$?\s*-?\d{1,3}(?:,\d{3})*\.\d{2}\s*$"#, options: .regularExpression) != nil {
            return (.amount, "")
        }
        
        // Date-only
        if t.range(of: #"^\d{1,2}[/\-]\d{1,2}[/\-]\d{2,4}$"#, options: .regularExpression) != nil { return (.text, "") }
        if t.range(of: #"^\d{4}[/\-]\d{1,2}[/\-]\d{1,2}$"#, options: .regularExpression) != nil { return (.text, "") }
        
        // Quantity
        if t.range(of: #"^\d{1,2}$"#, options: .regularExpression) != nil && (Int(t) ?? 0) < 100 { return (.text, "") }
        
        // Identifier cells (addresses, phones, account numbers)
        if looksLikeIdentifierCell(u) { return (.text, "") }
        
        // CPT (5-digit)
        if let r = u.range(of: #"\b\d{5}\b"#, options: .regularExpression) {
            let code = String(u[r])
            if isValidCPT(code) && isIsolatedCode(u, matchRange: r) { return (.code, code) }
        }
        // HCPCS
        if let r = u.range(of: #"\b[A-V]\d{4}\b"#, options: .regularExpression) {
            if isIsolatedCode(u, matchRange: r) { return (.code, String(u[r])) }
        }
        // ICD-10
        if let r = u.range(of: #"\b[A-TV-Z]\d{2}\.?\d{0,4}\b"#, options: .regularExpression) {
            let code = String(u[r])
            if code.count >= 3 && isIsolatedCode(u, matchRange: r) { return (.code, code) }
        }
        return (.text, "")
    }
    
    // MARK: - Code Type Detection
    
    static func detectType(_ code: String) -> MedicalCodeType? {
        let u = code.uppercased()
        if u.range(of: #"^\d{5}$"#, options: .regularExpression) != nil && isValidCPT(u) { return .cpt }
        if u.range(of: #"^[A-V]\d{4}$"#, options: .regularExpression) != nil { return .hcpcs }
        if u.range(of: #"^[A-TV-Z]\d{2}\.?\d{0,4}$"#, options: .regularExpression) != nil { return .icd10 }
        return nil
    }
    
    // MARK: - CPT Validation
    
    static func isValidCPT(_ code: String) -> Bool {
        guard code.count == 5, let n = Int(code) else { return false }
        return (n >= 100 && n <= 1999) || (n >= 10004 && n <= 69990) ||
               (n >= 70010 && n <= 79999) || (n >= 80047 && n <= 89398) ||
               (n >= 90281 && n <= 99607)
    }
    
    // MARK: - Isolation Check
    
    static func isIsolatedCode(_ text: String, matchRange: Range<String.Index>) -> Bool {
        let full = text
        if matchRange.lowerBound > full.startIndex {
            let prevIdx = full.index(before: matchRange.lowerBound)
            let prev = full[prevIdx]
            if prev.isNumber { return false }
            if prev == "-" && prevIdx > full.startIndex {
                let bh = full.index(before: prevIdx)
                if full[bh].isNumber { return false }
            }
        }
        if matchRange.upperBound < full.endIndex {
            let next = full[matchRange.upperBound]
            if next.isNumber { return false }
            if next == "-" {
                let ah = full.index(after: matchRange.upperBound)
                if ah < full.endIndex && full[ah].isNumber { return false }
            }
        }
        // Zip code guard
        let codeStr = String(full[matchRange])
        if codeStr.range(of: #"^\d{5}$"#, options: .regularExpression) != nil {
            let before = String(full[full.startIndex..<matchRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            if before.count >= 2 {
                let lastTwo = String(before.suffix(2)).uppercased()
                let states: Set<String> = ["AL","AK","AZ","AR","CA","CO","CT","DE","FL","GA","HI",
                    "IL","IN","IA","KS","KY","LA","ME","MD","MA","MI","MN","MS","MO","MT","NE","NV",
                    "NH","NJ","NM","NY","NC","ND","OH","OK","OR","PA","RI","SC","SD","TN","TX","UT",
                    "VT","VA","WA","WV","WI","WY","DC"]
                if states.contains(lastTwo) {
                    let bs = before.dropLast(2).trimmingCharacters(in: .whitespaces)
                    if bs.isEmpty || !bs.last!.isLetter { return false }
                }
            }
        }
        return true
    }
    
    // MARK: - Identifier Detection
    
    static func looksLikeIdentifierCell(_ text: String) -> Bool {
        let u = text.uppercased()
        let patterns = [
            #"(?:ACCT|ACCOUNT|POLICY|MRN|AET|ID\s*#?)[\s#:.\-]*\d"#,
            #"\(\d{3}\)\s*\d{3}"#,
            #"\d{3}[\-\.]\d{3}[\-\.]\d{4}"#,
            #"(?:FAX|PHONE|TEL|PH)[\s:]*"#,
            #"PO\s+BOX"#,
            #"\d+\s+\w+\s+(?:DRIVE|DR|STREET|ST|AVE|AVENUE|BLVD|ROAD|RD|WAY|LN|LANE|CT|COURT)"#,
            #"WWW\.\w+|HTTP"#,
        ]
        for pat in patterns {
            if u.range(of: pat, options: .regularExpression) != nil { return true }
        }
        return false
    }
    
    // MARK: - Inline Code Finder
    
    struct InlineMatch { let code: String; let type: MedicalCodeType }
    
    static func findInlineCode(_ text: String) -> InlineMatch? {
        let u = text.uppercased()
        if let r = u.range(of: #"\b\d{5}\b"#, options: .regularExpression), isValidCPT(String(u[r])), isIsolatedCode(u, matchRange: r) {
            return InlineMatch(code: String(u[r]), type: .cpt)
        }
        if let r = u.range(of: #"\b[A-V]\d{4}\b"#, options: .regularExpression), isIsolatedCode(u, matchRange: r) {
            return InlineMatch(code: String(u[r]), type: .hcpcs)
        }
        if let r = u.range(of: #"\b[A-TV-Z]\d{2}\.?\d{0,4}\b"#, options: .regularExpression), String(u[r]).count >= 3, isIsolatedCode(u, matchRange: r) {
            return InlineMatch(code: String(u[r]), type: .icd10)
        }
        return nil
    }
    
    // MARK: - Amount Parsing
    
    static func parseAmount(_ text: String) -> Double? {
        Double(text.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces))
    }
    
    static func lastAmount(in text: String) -> Double? {
        guard let rx = try? NSRegularExpression(pattern: #"\$?\s*(\d{1,3}(?:,\d{3})*\.\d{2})"#) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        let matches = rx.matches(in: text, range: range)
        guard let last = matches.last, let r = Range(last.range(at: 1), in: text) else { return nil }
        return Double(text[r].replacingOccurrences(of: ",", with: ""))
    }
    
    // MARK: - Column-Aware Row Builder
    
    /// Parse OCR cells into structured rows with code, description, and amount.
    /// This is the core logic from ScannerView's `buildCodesFromColumns`.
    static func buildRows(from cells: [OCRTextCell]) -> [ParsedBillRow] {
        guard !cells.isEmpty else { return [] }
        
        struct Tagged {
            let cell: OCRTextCell
            let kind: OCRCellKind
            let extractedCode: String
        }
        
        let tagged: [Tagged] = cells.map {
            let (k, c) = classifyCell($0.text)
            return Tagged(cell: $0, kind: k, extractedCode: c)
        }
        
        let codeTagged   = tagged.filter { $0.kind == .code }
        let amountTagged = tagged.filter { $0.kind == .amount }
        
        // Group into rows by Y
        let sorted = tagged.sorted { $0.cell.midY > $1.cell.midY }
        var rows: [[Tagged]] = []
        var curRow: [Tagged] = []
        var anchorY: CGFloat = -1
        let yTol: CGFloat = 0.010
        
        for item in sorted {
            if anchorY < 0 || abs(item.cell.midY - anchorY) <= yTol {
                curRow.append(item)
                if anchorY < 0 { anchorY = item.cell.midY }
            } else {
                if !curRow.isEmpty { rows.append(curRow.sorted { $0.cell.midX < $1.cell.midX }) }
                curRow = [item]; anchorY = item.cell.midY
            }
        }
        if !curRow.isEmpty { rows.append(curRow.sorted { $0.cell.midX < $1.cell.midX }) }
        
        let codeColX:   CGFloat? = codeTagged.isEmpty   ? nil : codeTagged.map(\.cell.midX).reduce(0, +) / CGFloat(codeTagged.count)
        let amountColX: CGFloat? = amountTagged.isEmpty ? nil : amountTagged.map(\.cell.midX).reduce(0, +) / CGFloat(amountTagged.count)
        
        var parsed: [ParsedBillRow] = []
        
        for row in rows {
            let codeCells = row.filter { $0.kind == .code }
            let amountCells = row.filter { $0.kind == .amount }
            let textCells = row.filter { $0.kind == .text }
            
            if codeCells.count > 1 {
                // Multiple codes in one row — split
                for codeItem in codeCells {
                    var pr = ParsedBillRow()
                    pr.code = codeItem.extractedCode
                    pr.codeType = detectType(codeItem.extractedCode)
                    pr.rawTexts = row.map(\.cell.text)
                    if let nearest = amountCells.min(by: { abs($0.cell.midX - codeItem.cell.midX) < abs($1.cell.midX - codeItem.cell.midX) }) {
                        pr.amount = parseAmount(nearest.cell.text)
                    }
                    pr.description = textCells
                        .filter { abs($0.cell.midY - codeItem.cell.midY) < 0.008 }
                        .sorted { $0.cell.midX < $1.cell.midX }
                        .map(\.cell.text).joined(separator: " ")
                    parsed.append(pr)
                }
            } else {
                var pr = ParsedBillRow()
                var descParts: [String] = []
                
                for item in row {
                    pr.rawTexts.append(item.cell.text)
                    switch item.kind {
                    case .code:
                        if pr.code.isEmpty {
                            pr.code = item.extractedCode
                            pr.codeType = detectType(item.extractedCode)
                        } else {
                            descParts.append(item.cell.text)
                        }
                    case .amount:
                        if pr.amount == nil || (amountColX != nil && abs(item.cell.midX - amountColX!) < 0.15) {
                            pr.amount = parseAmount(item.cell.text)
                        }
                    case .text:
                        if let cx = codeColX, abs(item.cell.midX - cx) < 0.08 { continue }
                        if let ax = amountColX, abs(item.cell.midX - ax) < 0.08 { continue }
                        descParts.append(item.cell.text)
                    }
                }
                
                // Try inline code extraction if no code found
                if pr.code.isEmpty {
                    let combined = row.map(\.cell.text).joined(separator: " ")
                    if let found = findInlineCode(combined) {
                        pr.code = found.code; pr.codeType = found.type
                        descParts = [combined.replacingOccurrences(of: found.code, with: "", options: .caseInsensitive)]
                        if pr.amount == nil { pr.amount = lastAmount(in: combined) }
                    }
                }
                
                if pr.code.isEmpty {
                    for item in row where item.kind == .text {
                        if let found = findInlineCode(item.cell.text) {
                            pr.code = found.code; pr.codeType = found.type
                            break
                        }
                    }
                }
                
                // Clean description
                pr.description = descParts.joined(separator: " ")
                    .trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "|-:·,"))
                    .trimmingCharacters(in: .whitespaces)
                
                // Strip amounts and dates from description
                if let rx = try? NSRegularExpression(pattern: #"\$?\s*-?\d{1,3}(?:,\d{3})*\.\d{2}"#) {
                    let range = NSRange(pr.description.startIndex..., in: pr.description)
                    pr.description = rx.stringByReplacingMatches(in: pr.description, range: range, withTemplate: "")
                        .trimmingCharacters(in: .whitespaces)
                }
                if let rx = try? NSRegularExpression(pattern: #"\d{1,2}/\d{1,2}/\d{2,4}"#) {
                    let range = NSRange(pr.description.startIndex..., in: pr.description)
                    pr.description = rx.stringByReplacingMatches(in: pr.description, range: range, withTemplate: "")
                        .trimmingCharacters(in: .whitespaces)
                }
                
                if !pr.code.isEmpty { parsed.append(pr) }
            }
        }
        
        return parsed
    }
    
    // MARK: - Enrich with Database Lookup
    
    /// Look up codes in CloudKitService and fill in descriptions
    @MainActor
    static func enrichRows(_ rows: [ParsedBillRow], using cloudKit: CloudKitService) -> [ParsedBillRow] {
        rows.map { row in
            var enriched = row
            if let match = cloudKit.lookupCode(row.code) {
                if enriched.description.count < 5 {
                    enriched.description = match.shortDescription
                }
            }
            return enriched
        }
    }
}
