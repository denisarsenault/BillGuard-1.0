//
//  MedicalCode.swift
//  BillGuard
//
//  Model representing a medical code (CPT, ICD-10, HCPCS)
//

import Foundation
import CloudKit

// MARK: - Code Type Enum

public enum MedicalCodeType: String, Codable, CaseIterable {
    case cpt = "CPT"
    case icd10 = "ICD-10"
    case icd10pcs = "ICD-10-PCS"
    case hcpcs = "HCPCS"
    
    public var displayName: String {
        switch self {
        case .cpt: return "CPT (Procedure)"
        case .icd10: return "ICD-10 (Diagnosis)"
        case .icd10pcs: return "ICD-10-PCS (Inpatient Procedure)"
        case .hcpcs: return "HCPCS (Supply/Service)"
        }
    }
    
    public var color: String {
        switch self {
        case .cpt: return "cptBlue"
        case .icd10: return "icd10Green"
        case .icd10pcs: return "icd10pcsGreen"
        case .hcpcs: return "hcpcsOrange"
        }
    }
}

// MARK: - Medical Code Model

public struct MedicalCode: Identifiable, Codable, Hashable {
    
    public let id: String
    public let code: String
    public let codeType: MedicalCodeType
    public let shortDescription: String
    public let plainEnglishDescription: String
    public let category: String
    public let subcategory: String?
    
    // Pricing
    public let priceLow: Double?
    public let priceAverage: Double?
    public let priceHigh: Double?
    
    // Additional info
    public let commonUses: [String]
    public let insuranceNotes: String?
    public let misuseWarning: String?
    public let relatedCodes: [String]
    public let keywords: [String]
    
    // Metadata
    public let lastUpdated: Date
    
    // MARK: - Computed Properties
    
    public var formattedPriceRange: String {
        guard let low = priceLow, let high = priceHigh else {
            return "Price data unavailable"
        }
        return "$\(Int(low)) – $\(Int(high))"
    }
    
    public var formattedAveragePrice: String {
        guard let avg = priceAverage else {
            return "N/A"
        }
        return "$\(Int(avg))"
    }
    
    public var hasValidPricing: Bool {
        return priceLow != nil && priceHigh != nil
    }
    
    // MARK: - CloudKit Record Type
    
    public static let recordType = "MedicalCode"
    
    // MARK: - CloudKit Field Keys
    
    enum CloudKitKeys: String {
        case code
        case codeType
        case shortDescription
        case plainEnglishDescription
        case category
        case subcategory
        case priceLow
        case priceAverage
        case priceHigh
        case commonUses
        case insuranceNotes
        case misuseWarning
        case relatedCodes
        case keywords
        case lastUpdated
    }
    
    // MARK: - Initialize from CloudKit Record
    
    init?(from record: CKRecord) {
        guard let code = record[CloudKitKeys.code.rawValue] as? String,
              let codeTypeString = record[CloudKitKeys.codeType.rawValue] as? String,
              let codeType = MedicalCodeType(rawValue: codeTypeString),
              let shortDescription = record[CloudKitKeys.shortDescription.rawValue] as? String,
              let plainEnglishDescription = record[CloudKitKeys.plainEnglishDescription.rawValue] as? String,
              let category = record[CloudKitKeys.category.rawValue] as? String else {
            return nil
        }
        
        self.id = record.recordID.recordName
        self.code = code
        self.codeType = codeType
        self.shortDescription = shortDescription
        self.plainEnglishDescription = plainEnglishDescription
        self.category = category
        self.subcategory = record[CloudKitKeys.subcategory.rawValue] as? String
        
        self.priceLow = record[CloudKitKeys.priceLow.rawValue] as? Double
        self.priceAverage = record[CloudKitKeys.priceAverage.rawValue] as? Double
        self.priceHigh = record[CloudKitKeys.priceHigh.rawValue] as? Double
        
        self.commonUses = record[CloudKitKeys.commonUses.rawValue] as? [String] ?? []
        self.insuranceNotes = record[CloudKitKeys.insuranceNotes.rawValue] as? String
        self.misuseWarning = record[CloudKitKeys.misuseWarning.rawValue] as? String
        self.relatedCodes = record[CloudKitKeys.relatedCodes.rawValue] as? [String] ?? []
        self.keywords = record[CloudKitKeys.keywords.rawValue] as? [String] ?? []
        
        self.lastUpdated = record[CloudKitKeys.lastUpdated.rawValue] as? Date ?? record.modificationDate ?? Date()
    }
    
    // MARK: - Convert to CloudKit Record
    
    func toRecord() -> CKRecord {
        let recordID = CKRecord.ID(recordName: id)
        let record = CKRecord(recordType: MedicalCode.recordType, recordID: recordID)
        
        record[CloudKitKeys.code.rawValue] = code as CKRecordValue
        record[CloudKitKeys.codeType.rawValue] = codeType.rawValue as CKRecordValue
        record[CloudKitKeys.shortDescription.rawValue] = shortDescription as CKRecordValue
        record[CloudKitKeys.plainEnglishDescription.rawValue] = plainEnglishDescription as CKRecordValue
        record[CloudKitKeys.category.rawValue] = category as CKRecordValue
        
        if let subcategory = subcategory {
            record[CloudKitKeys.subcategory.rawValue] = subcategory as CKRecordValue
        }
        
        if let priceLow = priceLow {
            record[CloudKitKeys.priceLow.rawValue] = priceLow as CKRecordValue
        }
        if let priceAverage = priceAverage {
            record[CloudKitKeys.priceAverage.rawValue] = priceAverage as CKRecordValue
        }
        if let priceHigh = priceHigh {
            record[CloudKitKeys.priceHigh.rawValue] = priceHigh as CKRecordValue
        }
        
        record[CloudKitKeys.commonUses.rawValue] = commonUses as CKRecordValue
        
        if let insuranceNotes = insuranceNotes {
            record[CloudKitKeys.insuranceNotes.rawValue] = insuranceNotes as CKRecordValue
        }
        if let misuseWarning = misuseWarning {
            record[CloudKitKeys.misuseWarning.rawValue] = misuseWarning as CKRecordValue
        }
        
        record[CloudKitKeys.relatedCodes.rawValue] = relatedCodes as CKRecordValue
        record[CloudKitKeys.keywords.rawValue] = keywords as CKRecordValue
        record[CloudKitKeys.lastUpdated.rawValue] = lastUpdated as CKRecordValue
        
        return record
    }
    
    // MARK: - Manual Initializer
    
    init(id: String = UUID().uuidString,
         code: String,
         codeType: MedicalCodeType,
         shortDescription: String,
         plainEnglishDescription: String,
         category: String,
         subcategory: String? = nil,
         priceLow: Double? = nil,
         priceAverage: Double? = nil,
         priceHigh: Double? = nil,
         commonUses: [String] = [],
         insuranceNotes: String? = nil,
         misuseWarning: String? = nil,
         relatedCodes: [String] = [],
         keywords: [String] = [],
         lastUpdated: Date = Date()) {
        
        self.id = id
        self.code = code
        self.codeType = codeType
        self.shortDescription = shortDescription
        self.plainEnglishDescription = plainEnglishDescription
        self.category = category
        self.subcategory = subcategory
        self.priceLow = priceLow
        self.priceAverage = priceAverage
        self.priceHigh = priceHigh
        self.commonUses = commonUses
        self.insuranceNotes = insuranceNotes
        self.misuseWarning = misuseWarning
        self.relatedCodes = relatedCodes
        self.keywords = keywords
        self.lastUpdated = lastUpdated
    }
}

// MARK: - Sample Data for Preview/Testing

extension MedicalCode {
    
    /// All medical codes loaded from the bundled JSON file
    public static let sampleCodes: [MedicalCode] = {
        let t0 = CFAbsoluteTimeGetCurrent()
        
        let jsonURL = Bundle.main.url(forResource: "medical_codes", withExtension: "json")
            ?? Bundle.main.url(forResource: "medical_codes", withExtension: "json", subdirectory: "Resources")
        
        guard let url = jsonURL else {
            print("⏱️ [MedicalCode] JSON not found — using defaults")
            return defaultSampleCodes
        }
        
        do {
            let data = try Data(contentsOf: url)
            let t1 = CFAbsoluteTimeGetCurrent()
            print("⏱️ [MedicalCode] File read: \(Int((t1-t0)*1000))ms (\(data.count) bytes)")
            
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let jsonCodes = try decoder.decode([JSONMedicalCode].self, from: data)
            let t2 = CFAbsoluteTimeGetCurrent()
            print("⏱️ [MedicalCode] JSON decode: \(Int((t2-t1)*1000))ms (\(jsonCodes.count) codes)")
            
            let codes = jsonCodes.map { $0.toMedicalCode() }
            let t3 = CFAbsoluteTimeGetCurrent()
            print("⏱️ [MedicalCode] Map: \(Int((t3-t2)*1000))ms")
            print("⏱️ [MedicalCode] TOTAL: \(Int((t3-t0)*1000))ms")
            
            return codes
        } catch {
            print("⏱️ [MedicalCode] DECODE FAILED: \(error.localizedDescription)")
            return defaultSampleCodes
        }
    }()
    
    /// Default fallback codes if JSON fails to load
    private static let defaultSampleCodes: [MedicalCode] = [
        MedicalCode(
            id: "cpt_99213",
            code: "99213",
            codeType: .cpt,
            shortDescription: "Office visit, established patient",
            plainEnglishDescription: "A standard office visit for a patient who has seen this doctor before.",
            category: "Evaluation and Management",
            subcategory: "Office Visits",
            priceLow: 55,
            priceAverage: 105,
            priceHigh: 180,
            commonUses: ["Routine follow-up", "Medication check", "Minor health concerns"],
            insuranceNotes: "Most insurance plans cover this as a standard office visit.",
            relatedCodes: ["99212", "99214"],
            keywords: ["office visit", "follow up", "established"]
        ),
        MedicalCode(
            id: "cpt_99214",
            code: "99214",
            codeType: .cpt,
            shortDescription: "Office visit, established patient (extended)",
            plainEnglishDescription: "An extended office visit for an established patient with complex issues.",
            category: "Evaluation and Management",
            subcategory: "Office Visits",
            priceLow: 95,
            priceAverage: 165,
            priceHigh: 275,
            commonUses: ["Complex chronic disease", "Multiple concerns", "Treatment changes"],
            insuranceNotes: "Higher copay than 99213.",
            relatedCodes: ["99213", "99215"],
            keywords: ["office visit", "extended", "complex"]
        ),
        MedicalCode(
            id: "cpt_99212",
            code: "99212",
            codeType: .cpt,
            shortDescription: "Office visit, established patient (brief)",
            plainEnglishDescription: "A brief office visit for simple health issues.",
            category: "Evaluation and Management",
            subcategory: "Office Visits",
            priceLow: 35,
            priceAverage: 65,
            priceHigh: 110,
            commonUses: ["Quick follow-up", "Prescription refill", "Minor issue"],
            insuranceNotes: "Lower copay than 99213.",
            relatedCodes: ["99211", "99213"],
            keywords: ["office visit", "brief", "quick"]
        ),
        MedicalCode(
            id: "cpt_70450",
            code: "70450",
            codeType: .cpt,
            shortDescription: "CT scan, head/brain, without contrast",
            plainEnglishDescription: "A CT scan of your head and brain without contrast dye.",
            category: "Radiology",
            subcategory: "CT Scans",
            priceLow: 200,
            priceAverage: 525,
            priceHigh: 1200,
            commonUses: ["Head injury", "Stroke symptoms", "Severe headaches"],
            insuranceNotes: "May require prior authorization.",
            relatedCodes: ["70460", "70470"],
            keywords: ["ct scan", "head", "brain", "imaging"]
        ),
        MedicalCode(
            id: "icd10_J06.9",
            code: "J06.9",
            codeType: .icd10,
            shortDescription: "Acute upper respiratory infection",
            plainEnglishDescription: "A diagnosis code for common upper respiratory infections like the common cold.",
            category: "Respiratory",
            subcategory: "Infections",
            priceLow: nil,
            priceAverage: nil,
            priceHigh: nil,
            commonUses: ["Common cold", "Sinus congestion", "Sore throat"],
            insuranceNotes: "This is a diagnosis code, not a procedure.",
            relatedCodes: ["J00", "J02.9"],
            keywords: ["cold", "respiratory", "infection", "uri"]
        ),
        MedicalCode(
            id: "cpt_93000",
            code: "93000",
            codeType: .cpt,
            shortDescription: "Electrocardiogram (ECG/EKG), complete",
            plainEnglishDescription: "A complete electrocardiogram recording the electrical activity of your heart.",
            category: "Cardiovascular",
            subcategory: "Diagnostic Tests",
            priceLow: 25,
            priceAverage: 75,
            priceHigh: 200,
            commonUses: ["Chest pain", "Heart rhythm problems", "Pre-surgery screening"],
            insuranceNotes: "Usually covered with minimal copay.",
            relatedCodes: ["93005", "93010"],
            keywords: ["ekg", "ecg", "heart test", "cardiac"]
        )
    ]
    
    public static var sample: MedicalCode {
        sampleCodes.first ?? defaultSampleCodes[0]
    }
}

// MARK: - JSON Decoding Helper

private struct JSONMedicalCode: Codable {
    public let recordName: String
    public let code: String
    public let codeType: String
    public let shortDescription: String
    public let plainEnglishDescription: String
    public let category: String
    public let subcategory: String?
    public let priceLow: Double?
    public let priceAverage: Double?
    public let priceHigh: Double?
    public let commonUses: [String]?
    public let insuranceNotes: String?
    public let misuseWarning: String?
    public let relatedCodes: [String]?
    public let keywords: [String]?
    public let lastUpdated: String?
    
    func toMedicalCode() -> MedicalCode {
        let codeTypeEnum: MedicalCodeType
        switch codeType.uppercased() {
        case "CPT": codeTypeEnum = .cpt
        case "ICD-10", "ICD10": codeTypeEnum = .icd10
        case "ICD-10-PCS", "ICD10PCS", "ICD10-PCS": codeTypeEnum = .icd10pcs
        case "HCPCS": codeTypeEnum = .hcpcs
        default: codeTypeEnum = .cpt
        }
        
        var date = Date()
        if let lastUpdated = lastUpdated {
            let formatter = ISO8601DateFormatter()
            date = formatter.date(from: lastUpdated) ?? Date()
        }
        
        return MedicalCode(
            id: recordName,
            code: code,
            codeType: codeTypeEnum,
            shortDescription: shortDescription,
            plainEnglishDescription: plainEnglishDescription,
            category: category,
            subcategory: subcategory,
            priceLow: priceLow,
            priceAverage: priceAverage,
            priceHigh: priceHigh,
            commonUses: commonUses ?? [],
            insuranceNotes: insuranceNotes,
            misuseWarning: misuseWarning,
            relatedCodes: relatedCodes ?? [],
            keywords: keywords ?? [],
            lastUpdated: date
        )
    }
}
