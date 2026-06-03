//
//  ScannerViewModel.swift
//  BillGuard
//
//  ViewModel for scanning and parsing medical codes
//

import Foundation
import SwiftUI

// MARK: - Scanned Code Model

struct ScannedCode: Identifiable, Equatable {
    let id = UUID()
    let rawText: String
    var detectedCode: String
    let scannedDescription: String  // The text from the scanned line (excluding the code itself)
    let possibleType: MedicalCodeType?
    let timestamp: Date
    var matchedMedicalCode: MedicalCode?
    var isLookingUp: Bool = false
    var lookupFailed: Bool = false
    var scannedPrice: Double?       // Price extracted from the scanned line
    
    var displayType: String {
        possibleType?.rawValue ?? "Unknown"
    }
    
    /// Returns the best available description
    var bestDescription: String {
        // Prefer the matched medical code's description, fall back to scanned text
        if let matched = matchedMedicalCode {
            return matched.shortDescription
        }
        return scannedDescription.isEmpty ? "No description available" : scannedDescription
    }
}

// MARK: - Scanner ViewModel

@MainActor
class ScannerViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var scannedCodes: [ScannedCode] = []
    @Published var isScanning = false
    @Published var errorMessage: String?
    @Published var lastScannedText: String = ""
    
    // MARK: - Dependencies
    
    var cloudKitService: CloudKitService
    
    // MARK: - Private Properties
    
    private var processedTexts: Set<String> = []
    
    // MARK: - Regex Patterns
    
    // CPT: 5 digits (00100-99499)
    private let cptPattern = "\\b([0-9]{5})\\b"
    
    // ICD-10-CM (Diagnosis): Letter + 2 digits + optional (. + 1-4 alphanumeric)
    private let icd10Pattern = "\\b([A-TV-Z][0-9]{2}(?:\\.[0-9A-Z]{1,4})?)\\b"
    
    // ICD-10-PCS (Procedure): 7 alphanumeric characters (starts with 0-9 or B-H, X, Y)
    private let icd10pcsPattern = "\\b([0-9B-HX-Y][0-9A-HJ-NP-Z]{6})\\b"
    
    // HCPCS: Letter + 4 digits
    private let hcpcsPattern = "\\b([A-V][0-9]{4})\\b"
    
    // MARK: - Initialization
    
    init(cloudKitService: CloudKitService) {
        self.cloudKitService = cloudKitService
    }
    
    // MARK: - Public Methods
    
    /// Process a single tapped line of text and extract medical codes
    func processTappedText(_ text: String) {
        let normalizedText = text.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        lastScannedText = text
        
        // Extract codes from the text
        var foundCodes: [ScannedCode] = []
        
        // Check for ICD-10-PCS codes first (7 chars, more specific)
        foundCodes.append(contentsOf: extractCodes(from: normalizedText, originalText: text, pattern: icd10pcsPattern, type: .icd10pcs))
        
        // Check for CPT codes (only if not already found as ICD-10-PCS)
        let cptCodes = extractCodes(from: normalizedText, originalText: text, pattern: cptPattern, type: .cpt)
        for code in cptCodes {
            // Avoid adding CPT codes that are part of ICD-10-PCS codes
            if !foundCodes.contains(where: { $0.detectedCode.contains(code.detectedCode) }) {
                foundCodes.append(code)
            }
        }
        
        // Check for ICD-10-CM codes
        foundCodes.append(contentsOf: extractCodes(from: normalizedText, originalText: text, pattern: icd10Pattern, type: .icd10))
        
        // Check for HCPCS codes
        foundCodes.append(contentsOf: extractCodes(from: normalizedText, originalText: text, pattern: hcpcsPattern, type: .hcpcs))
        
        // Add new codes that aren't duplicates
        for code in foundCodes {
            if !scannedCodes.contains(where: { $0.detectedCode == code.detectedCode }) {
                scannedCodes.insert(code, at: 0)
                
                // Look up the code in CloudKit
                Task {
                    await lookupCode(code)
                }
            }
        }
        
        // Mark text as processed to avoid re-adding on subsequent taps
        processedTexts.insert(normalizedText)
    }
    
    /// Process scanned text automatically (legacy - now only used for background detection display)
    func processScannedText(_ text: String) {
        // This method is now a no-op for automatic processing
        // Codes are only added when user taps
    }
    
    /// Process multiple lines of text (legacy)
    func processMultipleLines(_ lines: [String]) {
        // This method is now a no-op for automatic processing
        // Codes are only added when user taps
    }
    
    /// Remove a scanned code
    func removeCode(_ code: ScannedCode) {
        scannedCodes.removeAll { $0.id == code.id }
    }
    
    /// Remove code at index
    func removeCode(at offsets: IndexSet) {
        scannedCodes.remove(atOffsets: offsets)
    }
    
    /// Clear all scanned codes
    func clearAll() {
        scannedCodes.removeAll()
        processedTexts.removeAll()
        lastScannedText = ""
    }
    
    /// Reset scanner for new scanning session
    func resetScanner() {
        processedTexts.removeAll()
        lastScannedText = ""
    }
    
    // MARK: - Private Methods
    
    private func extractCodes(from text: String, originalText: String, pattern: String, type: MedicalCodeType) -> [ScannedCode] {
        var codes: [ScannedCode] = []
        
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [])
            let range = NSRange(text.startIndex..., in: text)
            let matches = regex.matches(in: text, options: [], range: range)
            
            for match in matches {
                if let codeRange = Range(match.range(at: 1), in: text) {
                    let codeString = String(text[codeRange])
                    
                    // Validate the code based on type
                    if isValidCode(codeString, type: type) {
                        // Extract description by removing the code from the original text
                        let description = extractDescription(from: originalText, removingCode: codeString)
                        
                        let scannedCode = ScannedCode(
                            rawText: originalText,
                            detectedCode: codeString,
                            scannedDescription: description,
                            possibleType: type,
                            timestamp: Date()
                        )
                        codes.append(scannedCode)
                    }
                }
            }
        } catch {
            print("Regex error: \(error)")
        }
        
        return codes
    }
    
    /// Extract description text from a line by removing the code
    private func extractDescription(from text: String, removingCode code: String) -> String {
        // Remove the code from the text
        var description = text.replacingOccurrences(of: code, with: "", options: .caseInsensitive)
        
        // Clean up common separators and extra whitespace
        description = description
            .replacingOccurrences(of: ":", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove leading/trailing punctuation
        description = description.trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.whitespaces))
        
        return description
    }
    
    private func isValidCode(_ code: String, type: MedicalCodeType) -> Bool {
        switch type {
        case .cpt:
            // CPT codes are 5 digits, typically in ranges
            guard code.count == 5, let numericValue = Int(code) else { return false }
            // Valid CPT ranges (simplified)
            return (numericValue >= 00100 && numericValue <= 01999) || // Anesthesia
                   (numericValue >= 10004 && numericValue <= 69990) || // Surgery
                   (numericValue >= 70010 && numericValue <= 79999) || // Radiology
                   (numericValue >= 80047 && numericValue <= 89398) || // Path/Lab
                   (numericValue >= 90281 && numericValue <= 99607)    // Medicine/E&M
            
        case .icd10:
            // ICD-10 starts with a letter (not U), followed by 2 digits
            guard code.count >= 3 else { return false }
            let firstChar = code.first!
            return firstChar.isLetter && firstChar != "U"
            
        case .icd10pcs:
            // ICD-10-PCS: 7 alphanumeric characters
            guard code.count == 7 else { return false }
            // First character is 0-9 or specific letters (body system)
            let firstChar = code.first!
            return firstChar.isNumber || "BCDFGHJKLMNPQRSTVWXY".contains(firstChar)
            
        case .hcpcs:
            // HCPCS Level II: A-V followed by 4 digits
            guard code.count == 5 else { return false }
            let firstChar = code.first!
            return firstChar.isLetter && firstChar >= "A" && firstChar <= "V"
        }
    }
    
    private func lookupCode(_ scannedCode: ScannedCode) async {
        guard let index = scannedCodes.firstIndex(where: { $0.id == scannedCode.id }) else { return }
        
        scannedCodes[index].isLookingUp = true
        
        do {
            if let medicalCode = try await cloudKitService.fetchCode(byCode: scannedCode.detectedCode) {
                scannedCodes[index].matchedMedicalCode = medicalCode
                scannedCodes[index].isLookingUp = false
            } else {
                // Try offline/sample data
                scannedCodes[index].matchedMedicalCode = cloudKitService.lookupCode(scannedCode.detectedCode)
                scannedCodes[index].isLookingUp = false
                scannedCodes[index].lookupFailed = scannedCodes[index].matchedMedicalCode == nil
            }
        } catch {
            // Try offline fallback
            scannedCodes[index].matchedMedicalCode = cloudKitService.lookupCode(scannedCode.detectedCode)
            scannedCodes[index].isLookingUp = false
            scannedCodes[index].lookupFailed = scannedCodes[index].matchedMedicalCode == nil
        }
    }
}
