//
//  ScannedDocument.swift
//  BillGuard
//
//  Scanned document model with PDF storage and extracted text blocks
//

import Foundation
import CloudKit

// MARK: - Document Type

public enum ScannedDocumentType: String, Codable, CaseIterable {
    case invoice = "Invoice"
    case bill = "Bill"
    case receipt = "Receipt"
    case eob = "Explanation of Benefits"
    case insuranceCard = "Insurance Card"
    case businessCard = "Business Card"
    case prescription = "Prescription"
    case labResults = "Lab Results"
    case medicalRecords = "Medical Records"
    case referral = "Referral"
    case priorAuth = "Prior Authorization"
    case other = "Other"
    
    public var icon: String {
        switch self {
        case .invoice, .bill: return "doc.text.fill"
        case .receipt: return "receipt.fill"
        case .eob: return "doc.badge.ellipsis"
        case .insuranceCard: return "creditcard.fill"
        case .businessCard: return "person.crop.rectangle.fill"
        case .prescription: return "pills.fill"
        case .labResults: return "flask.fill"
        case .medicalRecords: return "folder.fill.badge.plus"
        case .referral: return "arrow.triangle.branch"
        case .priorAuth: return "checkmark.seal.fill"
        case .other: return "doc.fill"
        }
    }
}

// MARK: - Text Block (extracted from OCR)

public struct TextBlock: Codable, Hashable, Identifiable {
    public var id: String
    public var text: String
    public var confidence: Double      // OCR confidence 0-1
    public var boundingBox: CGRectData // Position in the image/PDF
    public var pageNumber: Int
    public var fieldType: FieldType?   // What type of data this might be
    public var isSelected: Bool        // User has selected this block
    public var mappedTo: String?       // What field the user mapped this to
    
    public init(
        id: String = UUID().uuidString,
        text: String,
        confidence: Double = 1.0,
        boundingBox: CGRectData,
        pageNumber: Int = 1,
        fieldType: FieldType? = nil,
        isSelected: Bool = false,
        mappedTo: String? = nil
    ) {
        self.id = id
        self.text = text
        self.confidence = confidence
        self.boundingBox = boundingBox
        self.pageNumber = pageNumber
        self.fieldType = fieldType
        self.isSelected = isSelected
        self.mappedTo = mappedTo
    }
}

// MARK: - Field Type (for auto-detection and mapping)

public enum FieldType: String, Codable, CaseIterable {
    // Names
    case patientName = "Patient Name"
    case providerName = "Provider Name"
    case subscriberName = "Subscriber Name"
    
    // Contact
    case phone = "Phone"
    case fax = "Fax"
    case email = "Email"
    case website = "Website"
    
    // Address
    case streetAddress = "Street Address"
    case city = "City"
    case state = "State"
    case zipCode = "ZIP Code"
    case fullAddress = "Full Address"
    
    // Insurance
    case memberId = "Member ID"
    case groupNumber = "Group Number"
    case policyNumber = "Policy Number"
    case rxBin = "RX BIN"
    case rxPcn = "RX PCN"
    case rxGroup = "RX Group"
    case carrierName = "Insurance Carrier"
    case planName = "Plan Name"
    
    // Financial
    case billedAmount = "Billed Amount"
    case allowedAmount = "Allowed Amount"
    case paidAmount = "Paid Amount"
    case patientOwes = "Patient Owes"
    case copay = "Copay"
    case deductible = "Deductible"
    case coinsurance = "Coinsurance"
    case totalDue = "Total Due"
    case accountNumber = "Account Number"
    
    // Dates
    case serviceDate = "Service Date"
    case billingDate = "Billing Date"
    case dueDate = "Due Date"
    case dateOfBirth = "Date of Birth"
    case effectiveDate = "Effective Date"
    
    // Codes
    case cptCode = "CPT Code"
    case icdCode = "ICD-10 Code"
    case npi = "NPI Number"
    case claimNumber = "Claim Number"
    
    // Other
    case unknown = "Unknown"
    
    public var icon: String {
        switch self {
        case .patientName, .providerName, .subscriberName:
            return "person.fill"
        case .phone, .fax:
            return "phone.fill"
        case .email:
            return "envelope.fill"
        case .website:
            return "globe"
        case .streetAddress, .city, .state, .zipCode, .fullAddress:
            return "mappin.circle.fill"
        case .memberId, .groupNumber, .policyNumber, .carrierName, .planName:
            return "creditcard.fill"
        case .rxBin, .rxPcn, .rxGroup:
            return "pills.fill"
        case .billedAmount, .allowedAmount, .paidAmount, .patientOwes, .copay, .deductible, .coinsurance, .totalDue:
            return "dollarsign.circle.fill"
        case .accountNumber:
            return "number"
        case .serviceDate, .billingDate, .dueDate, .dateOfBirth, .effectiveDate:
            return "calendar"
        case .cptCode, .icdCode, .npi, .claimNumber:
            return "barcode"
        case .unknown:
            return "questionmark.circle"
        }
    }
}

// MARK: - CGRect Data (Codable wrapper)

public struct CGRectData: Codable, Hashable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
    
    public init(from rect: CGRect) {
        self.x = Double(rect.origin.x)
        self.y = Double(rect.origin.y)
        self.width = Double(rect.size.width)
        self.height = Double(rect.size.height)
    }
    
    public var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}

// MARK: - Scanned Document Model

public struct ScannedDocument: Identifiable, Codable, Hashable {
    public var id: String
    public var patientId: String?
    public var visitId: String?
    public var providerId: String?
    public var claimId: String?
    
    // Document Info
    public var documentType: ScannedDocumentType
    public var name: String
    public var notes: String?
    
    // File Storage
    public var localFileName: String      // Local file name in app's documents
    public var cloudAssetId: String?      // CloudKit asset ID if uploaded
    public var thumbnailData: Data?       // Small preview image
    public var pageCount: Int
    public var fileSize: Int              // In bytes
    
    // OCR Results
    public var textBlocks: [TextBlock]
    public var fullText: String?          // Combined full text
    public var ocrProcessed: Bool
    public var ocrLanguage: String?
    
    // Extracted/Mapped Data
    public var extractedData: [String: String]?  // Key = FieldType.rawValue, Value = extracted text
    
    // Metadata
    public var scannedAt: Date
    public var createdAt: Date
    public var updatedAt: Date
    public var recordId: String?
    
    public init(
        id: String = UUID().uuidString,
        patientId: String? = nil,
        visitId: String? = nil,
        providerId: String? = nil,
        claimId: String? = nil,
        documentType: ScannedDocumentType = .other,
        name: String,
        notes: String? = nil,
        localFileName: String,
        cloudAssetId: String? = nil,
        thumbnailData: Data? = nil,
        pageCount: Int = 1,
        fileSize: Int = 0,
        textBlocks: [TextBlock] = [],
        fullText: String? = nil,
        ocrProcessed: Bool = false,
        ocrLanguage: String? = "en",
        extractedData: [String: String]? = nil,
        scannedAt: Date = Date(),
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        recordId: String? = nil
    ) {
        self.id = id
        self.patientId = patientId
        self.visitId = visitId
        self.providerId = providerId
        self.claimId = claimId
        self.documentType = documentType
        self.name = name
        self.notes = notes
        self.localFileName = localFileName
        self.cloudAssetId = cloudAssetId
        self.thumbnailData = thumbnailData
        self.pageCount = pageCount
        self.fileSize = fileSize
        self.textBlocks = textBlocks
        self.fullText = fullText
        self.ocrProcessed = ocrProcessed
        self.ocrLanguage = ocrLanguage
        self.extractedData = extractedData
        self.scannedAt = scannedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.recordId = recordId
    }
    
    // MARK: - Computed Properties
    
    public var localFileURL: URL? {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        return documentsPath?.appendingPathComponent(localFileName)
    }
    
    public var fileSizeFormatted: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(fileSize))
    }
    
    public var selectedBlocks: [TextBlock] {
        textBlocks.filter { $0.isSelected }
    }
    
    public var mappedBlocks: [TextBlock] {
        textBlocks.filter { $0.mappedTo != nil }
    }
    
    // MARK: - Methods
    
    mutating func selectBlock(id: String) {
        if let index = textBlocks.firstIndex(where: { $0.id == id }) {
            textBlocks[index].isSelected = true
        }
    }
    
    mutating func deselectBlock(id: String) {
        if let index = textBlocks.firstIndex(where: { $0.id == id }) {
            textBlocks[index].isSelected = false
            textBlocks[index].mappedTo = nil
        }
    }
    
    mutating func mapBlock(id: String, to fieldType: FieldType) {
        if let index = textBlocks.firstIndex(where: { $0.id == id }) {
            textBlocks[index].isSelected = true
            textBlocks[index].mappedTo = fieldType.rawValue
            textBlocks[index].fieldType = fieldType
            
            // Also store in extractedData
            if extractedData == nil {
                extractedData = [:]
            }
            extractedData?[fieldType.rawValue] = textBlocks[index].text
        }
    }
    
    public func getExtractedValue(for fieldType: FieldType) -> String? {
        extractedData?[fieldType.rawValue]
    }
}

// MARK: - CloudKit Support

extension ScannedDocument {
    static let recordType = "ScannedDocument"
    
    init?(from record: CKRecord) {
        guard record.recordType == ScannedDocument.recordType,
              let name = record["name"] as? String,
              let localFileName = record["localFileName"] as? String,
              let typeRaw = record["documentType"] as? String,
              let documentType = ScannedDocumentType(rawValue: typeRaw) else {
            return nil
        }
        
        self.id = record["id"] as? String ?? record.recordID.recordName
        self.patientId = record["patientId"] as? String
        self.visitId = record["visitId"] as? String
        self.providerId = record["providerId"] as? String
        self.claimId = record["claimId"] as? String
        self.documentType = documentType
        self.name = name
        self.notes = record["notes"] as? String
        self.localFileName = localFileName
        self.cloudAssetId = record["cloudAssetId"] as? String
        self.thumbnailData = record["thumbnailData"] as? Data
        self.pageCount = record["pageCount"] as? Int ?? 1
        self.fileSize = record["fileSize"] as? Int ?? 0
        
        if let blocksData = record["textBlocks"] as? Data {
            self.textBlocks = (try? JSONDecoder().decode([TextBlock].self, from: blocksData)) ?? []
        } else {
            self.textBlocks = []
        }
        
        self.fullText = record["fullText"] as? String
        self.ocrProcessed = record["ocrProcessed"] as? Bool ?? false
        self.ocrLanguage = record["ocrLanguage"] as? String
        
        if let extractedData = record["extractedData"] as? Data {
            self.extractedData = try? JSONDecoder().decode([String: String].self, from: extractedData)
        }
        
        self.scannedAt = record["scannedAt"] as? Date ?? Date()
        self.createdAt = record["createdAt"] as? Date ?? record.creationDate ?? Date()
        self.updatedAt = record["updatedAt"] as? Date ?? record.modificationDate ?? Date()
        self.recordId = record.recordID.recordName
    }
    
    func toRecord(existingRecord: CKRecord? = nil) -> CKRecord {
        let record = existingRecord ?? CKRecord(recordType: ScannedDocument.recordType)
        
        record["id"] = id
        record["patientId"] = patientId
        record["visitId"] = visitId
        record["providerId"] = providerId
        record["claimId"] = claimId
        record["documentType"] = documentType.rawValue
        record["name"] = name
        record["notes"] = notes
        record["localFileName"] = localFileName
        record["cloudAssetId"] = cloudAssetId
        record["thumbnailData"] = thumbnailData
        record["pageCount"] = pageCount
        record["fileSize"] = fileSize
        
        if let data = try? JSONEncoder().encode(textBlocks) {
            record["textBlocks"] = data
        }
        
        record["fullText"] = fullText
        record["ocrProcessed"] = ocrProcessed
        record["ocrLanguage"] = ocrLanguage
        
        if let extracted = extractedData, let data = try? JSONEncoder().encode(extracted) {
            record["extractedData"] = data
        }
        
        record["scannedAt"] = scannedAt
        record["createdAt"] = createdAt
        record["updatedAt"] = Date()
        
        return record
    }
}
