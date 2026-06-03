//
//  DocumentScannerService.swift
//  BillGuard
//
//  Service for scanning documents, performing OCR, and saving as PDFs
//

import Foundation
import Vision
import VisionKit
import UIKit
import PDFKit

@MainActor
class DocumentScannerService: ObservableObject {
    static let shared = DocumentScannerService()
    
    @Published var isProcessing = false
    @Published var processingProgress: Double = 0
    @Published var errorMessage: String?
    
    private init() {}
    
    // MARK: - Document Scanning Support Check
    
    var isScanningSupported: Bool {
        VNDocumentCameraViewController.isSupported
    }
    
    var isLiveTextSupported: Bool {
        if #available(iOS 16.0, *) {
            return DataScannerViewController.isSupported
        }
        return false
    }
    
    // MARK: - Process Scanned Images
    
    /// Process scanned images from VNDocumentCameraViewController
    func processScannedImages(
        _ images: [UIImage],
        documentType: ScannedDocumentType,
        patientId: String?
    ) async throws -> ScannedDocument {
        isProcessing = true
        processingProgress = 0
        errorMessage = nil
        
        defer {
            isProcessing = false
            processingProgress = 1.0
        }
        
        // Generate unique filename
        let timestamp = Date().timeIntervalSince1970
        let fileName = "scan_\(Int(timestamp)).pdf"
        
        // Create PDF from images
        let pdfURL = try await createPDF(from: images, fileName: fileName)
        processingProgress = 0.3
        
        // Get file size
        let fileAttributes = try FileManager.default.attributesOfItem(atPath: pdfURL.path)
        let fileSize = fileAttributes[.size] as? Int ?? 0
        
        // Generate thumbnail
        let thumbnail = await generateThumbnail(from: images.first)
        processingProgress = 0.4
        
        // Perform OCR on all pages
        var allTextBlocks: [TextBlock] = []
        var fullText = ""
        
        for (index, image) in images.enumerated() {
            let pageBlocks = try await performOCR(on: image, pageNumber: index + 1)
            allTextBlocks.append(contentsOf: pageBlocks)
            
            let pageText = pageBlocks.map { $0.text }.joined(separator: "\n")
            fullText += pageText + "\n\n"
            
            processingProgress = 0.4 + (0.5 * Double(index + 1) / Double(images.count))
        }
        
        // Auto-detect field types
        let enhancedBlocks = autoDetectFieldTypes(in: allTextBlocks)
        processingProgress = 0.95
        
        // Create document object
        let document = ScannedDocument(
            patientId: patientId,
            documentType: documentType,
            name: "\(documentType.rawValue) - \(formatDate(Date()))",
            localFileName: fileName,
            thumbnailData: thumbnail,
            pageCount: images.count,
            fileSize: fileSize,
            textBlocks: enhancedBlocks,
            fullText: fullText.trimmingCharacters(in: .whitespacesAndNewlines),
            ocrProcessed: true,
            ocrLanguage: "en"
        )
        
        return document
    }
    
    // MARK: - Create PDF from Images
    
    private func createPDF(from images: [UIImage], fileName: String) async throws -> URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let pdfURL = documentsPath.appendingPathComponent(fileName)
        
        let pdfDocument = PDFDocument()
        
        for (index, image) in images.enumerated() {
            if let page = PDFPage(image: image) {
                pdfDocument.insert(page, at: index)
            }
        }
        
        guard pdfDocument.write(to: pdfURL) else {
            throw DocumentScannerError.pdfCreationFailed
        }
        
        return pdfURL
    }
    
    // MARK: - OCR Processing
    
    private func performOCR(on image: UIImage, pageNumber: Int) async throws -> [TextBlock] {
        guard let cgImage = image.cgImage else {
            throw DocumentScannerError.invalidImage
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: [])
                    return
                }
                
                var textBlocks: [TextBlock] = []
                
                for observation in observations {
                    guard let topCandidate = observation.topCandidates(1).first else {
                        continue
                    }
                    
                    let boundingBox = observation.boundingBox
                    let block = TextBlock(
                        text: topCandidate.string,
                        confidence: Double(topCandidate.confidence),
                        boundingBox: CGRectData(from: boundingBox),
                        pageNumber: pageNumber
                    )
                    textBlocks.append(block)
                }
                
                continuation.resume(returning: textBlocks)
            }
            
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["en-US"]
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    // MARK: - Auto-Detect Field Types
    
    private func autoDetectFieldTypes(in blocks: [TextBlock]) -> [TextBlock] {
        return blocks.map { block in
            var updatedBlock = block
            updatedBlock.fieldType = detectFieldType(for: block.text)
            return updatedBlock
        }
    }
    
    private func detectFieldType(for text: String) -> FieldType? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = trimmed.lowercased()
        
        // Phone number patterns
        if matchesPattern(trimmed, pattern: #"^\(?\d{3}\)?[-.\s]?\d{3}[-.\s]?\d{4}$"#) {
            return .phone
        }
        
        // Email pattern
        if matchesPattern(trimmed, pattern: #"^[\w.+-]+@[\w-]+\.[\w.-]+$"#) {
            return .email
        }
        
        // ZIP code
        if matchesPattern(trimmed, pattern: #"^\d{5}(-\d{4})?$"#) {
            return .zipCode
        }
        
        // Date patterns (MM/DD/YYYY, MM-DD-YYYY, etc.)
        if matchesPattern(trimmed, pattern: #"^\d{1,2}[/-]\d{1,2}[/-]\d{2,4}$"#) {
            if lowercased.contains("service") || lowercased.contains("dos") {
                return .serviceDate
            } else if lowercased.contains("due") {
                return .dueDate
            } else if lowercased.contains("birth") || lowercased.contains("dob") {
                return .dateOfBirth
            }
            return .serviceDate  // Default date type
        }
        
        // Currency amounts
        if matchesPattern(trimmed, pattern: #"^\$?\d{1,3}(,\d{3})*(\.\d{2})?$"#) {
            if lowercased.contains("total") || lowercased.contains("due") {
                return .totalDue
            } else if lowercased.contains("copay") {
                return .copay
            } else if lowercased.contains("deductible") {
                return .deductible
            } else if lowercased.contains("billed") || lowercased.contains("charged") {
                return .billedAmount
            } else if lowercased.contains("paid") {
                return .paidAmount
            } else if lowercased.contains("patient") || lowercased.contains("owe") {
                return .patientOwes
            }
            return .billedAmount  // Default amount type
        }
        
        // Member ID patterns (letters and numbers, often with dashes)
        if matchesPattern(trimmed, pattern: #"^[A-Z]{2,3}\d{6,12}$"#) ||
           matchesPattern(trimmed, pattern: #"^\d{9,12}$"#) {
            return .memberId
        }
        
        // Group number patterns
        if lowercased.contains("group") && matchesPattern(trimmed, pattern: #"\d{4,10}"#) {
            return .groupNumber
        }
        
        // RX BIN (6 digits)
        if matchesPattern(trimmed, pattern: #"^\d{6}$"#) && lowercased.contains("bin") {
            return .rxBin
        }
        
        // NPI (10 digits)
        if matchesPattern(trimmed, pattern: #"^\d{10}$"#) {
            return .npi
        }
        
        // CPT codes (5 digits, sometimes with modifiers)
        if matchesPattern(trimmed, pattern: #"^\d{5}(-\d{2})?$"#) {
            return .cptCode
        }
        
        // ICD-10 codes
        if matchesPattern(trimmed, pattern: #"^[A-Z]\d{2}(\.\d{1,4})?$"#) {
            return .icdCode
        }
        
        // Claim number
        if lowercased.contains("claim") && matchesPattern(trimmed, pattern: #"[A-Z0-9]{8,20}"#) {
            return .claimNumber
        }
        
        // State abbreviations
        if USState.abbreviations.contains(trimmed.uppercased()) {
            return .state
        }
        
        // Keywords in text
        if lowercased.contains("patient name") || lowercased.contains("patient:") {
            return .patientName
        }
        
        if lowercased.contains("provider") || lowercased.contains("physician") || lowercased.contains("doctor") {
            return .providerName
        }
        
        if lowercased.contains("subscriber") {
            return .subscriberName
        }
        
        return nil
    }
    
    private func matchesPattern(_ text: String, pattern: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return false
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.firstMatch(in: text, options: [], range: range) != nil
    }
    
    // MARK: - Thumbnail Generation
    
    private func generateThumbnail(from image: UIImage?) async -> Data? {
        guard let image = image else { return nil }
        
        let thumbnailSize = CGSize(width: 150, height: 200)
        
        UIGraphicsBeginImageContextWithOptions(thumbnailSize, false, 1.0)
        image.draw(in: CGRect(origin: .zero, size: thumbnailSize))
        let thumbnail = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return thumbnail?.jpegData(compressionQuality: 0.6)
    }
    
    // MARK: - Load PDF from Document
    
    func loadPDF(for document: ScannedDocument) -> PDFDocument? {
        guard let url = document.localFileURL else { return nil }
        return PDFDocument(url: url)
    }
    
    // MARK: - Re-process OCR
    
    func reprocessOCR(for document: ScannedDocument) async throws -> ScannedDocument {
        guard let url = document.localFileURL,
              let pdfDocument = PDFDocument(url: url) else {
            throw DocumentScannerError.pdfNotFound
        }
        
        isProcessing = true
        processingProgress = 0
        
        defer {
            isProcessing = false
            processingProgress = 1.0
        }
        
        var allTextBlocks: [TextBlock] = []
        var fullText = ""
        
        for pageIndex in 0..<pdfDocument.pageCount {
            guard let page = pdfDocument.page(at: pageIndex) else {
                continue
            }
            
            let pageImage = page.thumbnail(of: CGSize(width: 1000, height: 1500), for: .mediaBox)
            
            let pageBlocks = try await performOCR(on: pageImage, pageNumber: pageIndex + 1)
            allTextBlocks.append(contentsOf: pageBlocks)
            
            let pageText = pageBlocks.map { $0.text }.joined(separator: "\n")
            fullText += pageText + "\n\n"
            
            processingProgress = Double(pageIndex + 1) / Double(pdfDocument.pageCount)
        }
        
        let enhancedBlocks = autoDetectFieldTypes(in: allTextBlocks)
        
        var updatedDocument = document
        updatedDocument.textBlocks = enhancedBlocks
        updatedDocument.fullText = fullText.trimmingCharacters(in: .whitespacesAndNewlines)
        updatedDocument.ocrProcessed = true
        updatedDocument.updatedAt = Date()
        
        return updatedDocument
    }
    
    // MARK: - Delete Document
    
    func deleteDocument(_ document: ScannedDocument) throws {
        guard let url = document.localFileURL else { return }
        
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
    
    // MARK: - Helpers
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

// MARK: - Errors

enum DocumentScannerError: LocalizedError {
    case pdfCreationFailed
    case invalidImage
    case pdfNotFound
    case ocrFailed
    
    var errorDescription: String? {
        switch self {
        case .pdfCreationFailed:
            return "Failed to create PDF from scanned images"
        case .invalidImage:
            return "Invalid image data"
        case .pdfNotFound:
            return "PDF file not found"
        case .ocrFailed:
            return "Failed to extract text from document"
        }
    }
}
