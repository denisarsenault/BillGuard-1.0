//
//  ParsedLineItem.swift
//  BillGuardCore
//
//  Output line item from the shared BillParser (editable in review). Extracted
//  from the iOS app so both platforms share one definition.
//

import Foundation

public enum LineItemKind {
    case charge    // a billed procedure/charge row
    case payment   // a payment, adjustment, credit, or transfer row
}

public struct ParsedLineItem: Identifiable {
    public let id = UUID()
    public var code: String
    public var description: String
    public var amount: Double
    public var isSelected: Bool = true
    public var codeType: MedicalCodeType?
    public var matchedMedicalCode: MedicalCode?
    public var lookupFailed: Bool = false
    public var kind: LineItemKind = .charge

    /// Best description — prefer database match over OCR text
    public var bestDescription: String {
        if let mc = matchedMedicalCode {
            return mc.shortDescription
        }
        return description
    }

    /// Database price range if available
    public var databasePriceRange: String? {
        guard let mc = matchedMedicalCode, mc.hasValidPricing else { return nil }
        return mc.formattedPriceRange
    }
}
