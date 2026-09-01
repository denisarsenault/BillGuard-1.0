//
//  ParsedLineItem.swift
//  BillGuardCore
//
//  Output line item from the shared BillParser (editable in review). Extracted
//  from the iOS app so both platforms share one definition.
//

import Foundation

enum LineItemKind {
    case charge    // a billed procedure/charge row
    case payment   // a payment, adjustment, credit, or transfer row
}

struct ParsedLineItem: Identifiable {
    let id = UUID()
    var code: String
    var description: String
    var amount: Double
    var isSelected: Bool = true
    var codeType: MedicalCodeType?
    var matchedMedicalCode: MedicalCode?
    var lookupFailed: Bool = false
    var kind: LineItemKind = .charge

    /// Best description — prefer database match over OCR text
    var bestDescription: String {
        if let mc = matchedMedicalCode {
            return mc.shortDescription
        }
        return description
    }

    /// Database price range if available
    var databasePriceRange: String? {
        guard let mc = matchedMedicalCode, mc.hasValidPricing else { return nil }
        return mc.formattedPriceRange
    }
}
