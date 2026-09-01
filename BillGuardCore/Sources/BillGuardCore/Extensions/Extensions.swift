//
//  Extensions.swift
//  BillGuard
//
//  Useful extensions for the app
//

import SwiftUI

// MARK: - Color Extensions

extension Color {
    
    // App theme colors
    static let appPrimary = Color.accentColor
    static let appBackground = Color("BrandDeepNavy")
    static let appSecondaryBackground = Color("BrandNavy")
    
    // Code type colors
    static let cptColor = Color("BrandCyan")
    static let icd10Color = Color.green
    static let hcpcsColor = Color.orange
    
    // Price colors
    static let priceLow = Color.green
    static let priceAverage = Color("BrandCyan")
    static let priceHigh = Color.orange
}

// MARK: - View Extensions

extension View {
    
    /// Apply card styling to a view
    func cardStyle() -> some View {
        self
            .padding()
            .background(Color("BrandDeepNavy"))
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
    
    /// Apply section header styling
    func sectionHeader() -> some View {
        self
            .font(.title3)
            .fontWeight(.semibold)
            .foregroundColor(.primary)
    }
    
    /// Hide keyboard (iOS/Catalyst only; no-op on macOS)
    func hideKeyboard() {
        #if canImport(UIKit)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif
    }
}

// MARK: - String Extensions

extension String {
    
    /// Check if string contains only numbers
    var isNumeric: Bool {
        return !isEmpty && rangeOfCharacter(from: CharacterSet.decimalDigits.inverted) == nil
    }
    
    /// Clean and normalize search text
    var normalizedForSearch: String {
        return self
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: ".", with: "")
    }
}

// MARK: - Date Extensions

extension Date {
    
    /// Format date as relative string (e.g., "2 hours ago")
    var relativeString: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }
    
    /// Format date as short date string
    var shortDateString: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter.string(from: self)
    }
}

// MARK: - Double Extensions

extension Double {
    
    /// Format as currency string
    var currencyString: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: self)) ?? "$\(Int(self))"
    }
}

// MARK: - Array Extensions

extension Array where Element == MedicalCode {
    
    /// Sort codes by relevance to search query
    func sortedByRelevance(to query: String) -> [MedicalCode] {
        let normalizedQuery = query.normalizedForSearch
        
        return self.sorted { code1, code2 in
            let code1Relevance = code1.relevanceScore(for: normalizedQuery)
            let code2Relevance = code2.relevanceScore(for: normalizedQuery)
            return code1Relevance > code2Relevance
        }
    }
}

extension MedicalCode {
    
    /// Calculate relevance score for search ranking
    func relevanceScore(for query: String) -> Int {
        var score = 0
        
        // Exact code match is highest priority
        if code.lowercased() == query {
            score += 100
        } else if code.lowercased().hasPrefix(query) {
            score += 50
        } else if code.lowercased().contains(query) {
            score += 25
        }
        
        // Description match
        if shortDescription.lowercased().contains(query) {
            score += 20
        }
        
        // Keyword match
        for keyword in keywords {
            if keyword.lowercased().contains(query) {
                score += 15
                break
            }
        }
        
        // Category match
        if category.lowercased().contains(query) {
            score += 10
        }
        
        return score
    }
}

// MARK: - Accessibility

extension View {
    
    /// Apply accessible font scaling
    func accessibleFont(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> some View {
        self.font(.system(style, design: .default, weight: weight))
    }
}

// MARK: - Preview Helpers

#if DEBUG
extension MedicalCode {
    static var previewCode: MedicalCode {
        MedicalCode.sampleCodes[0]
    }
}
#endif
