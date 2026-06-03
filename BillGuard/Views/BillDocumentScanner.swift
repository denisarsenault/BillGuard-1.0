//
//  BillDocumentScanner.swift
//  BillGuard
//
//  Enhanced bill scanning with detailed patient, provider, and procedure extraction
//

import SwiftUI
import Vision
import PhotosUI
import UniformTypeIdentifiers

// MARK: - Extracted Data Models

struct ExtractedPatientInfo: Codable, Equatable {
    var name: String = ""
    var address: String = ""
    var city: String = ""
    var state: String = ""
    var zipCode: String = ""
    var phone: String = ""
    var accountNumber: String = ""
    var dateOfBirth: String = ""
    var insurance: String = ""
    var policyNumber: String = ""
    var mrn: String = ""
    var dateOfService: String = ""
    var dischargeDate: String = ""
    
    var isValid: Bool {
        !name.isEmpty
    }
    
    var fullAddress: String {
        var parts: [String] = []
        if !address.isEmpty { parts.append(address) }
        var cityStateZip: [String] = []
        if !city.isEmpty { cityStateZip.append(city) }
        if !state.isEmpty { cityStateZip.append(state) }
        if !zipCode.isEmpty { cityStateZip.append(zipCode) }
        if !cityStateZip.isEmpty { parts.append(cityStateZip.joined(separator: ", ")) }
        return parts.joined(separator: "\n")
    }
}

struct ExtractedProviderInfo: Codable, Equatable {
    var name: String = ""
    var facilityName: String = ""
    var address: String = ""
    var city: String = ""
    var state: String = ""
    var zipCode: String = ""
    var phone: String = ""
    var fax: String = ""
    var npi: String = ""
    var taxId: String = ""
    
    var isValid: Bool {
        !name.isEmpty || !facilityName.isEmpty
    }
    
    var displayName: String {
        if !facilityName.isEmpty { return facilityName }
        return name
    }
}

struct ExtractedProcedureLine: Identifiable, Codable, Equatable {
    var id = UUID()
    var code: String = ""
    var codeType: String = "CPT"  // CPT, HCPCS, ICD-10, ICD-10-PCS
    var description: String = ""
    var quantity: Int = 1
    var unitCost: Double = 0
    var totalCost: Double = 0
    var serviceDate: Date = Date()
    var modifiers: [String] = []
    var diagnosisCodes: [String] = []  // ICD-10 diagnosis codes associated with this line
    
    // Matched from database
    var matchedCode: MedicalCode?
    var normalCostLow: Double?
    var normalCostHigh: Double?
    var normalCostAverage: Double?
    
    var hasCostComparison: Bool {
        normalCostLow != nil && normalCostHigh != nil
    }
    
    var costStatus: CostStatus {
        guard let low = normalCostLow, let high = normalCostHigh else { return .unknown }
        if totalCost < low { return .belowAverage }
        if totalCost > high { return .aboveAverage }
        return .withinRange
    }
    
    // Determine code type from the code format
    var detectedCodeType: String {
        if code.isEmpty { return "Unknown" }
        
        // HCPCS: Letter + 4 digits
        if let first = code.first, first.isLetter && code.count == 5 {
            let rest = code.dropFirst()
            if rest.allSatisfy({ $0.isNumber }) {
                return "HCPCS"
            }
        }
        
        // CPT: 5 digits
        if code.count == 5 && code.allSatisfy({ $0.isNumber }) {
            return "CPT"
        }
        
        // ICD-10: Letter + 2-3 digits, optionally with decimal
        if let first = code.first, first.isLetter {
            if code.contains(".") || (code.count >= 3 && code.count <= 7) {
                return "ICD-10"
            }
        }
        
        // ICD-10-PCS: 7 alphanumeric starting with digit
        if code.count == 7, let first = code.first, first.isNumber {
            return "ICD-10-PCS"
        }
        
        return "Unknown"
    }
    
    enum CostStatus {
        case belowAverage, withinRange, aboveAverage, unknown
        
        var color: Color {
            switch self {
            case .belowAverage: return .green
            case .withinRange: return .blue
            case .aboveAverage: return .orange
            case .unknown: return .gray
            }
        }
        
        var label: String {
            switch self {
            case .belowAverage: return "Below Average"
            case .withinRange: return "Normal Range"
            case .aboveAverage: return "Above Average"
            case .unknown: return "No Data"
            }
        }
    }
}

struct ExtractedBillData: Equatable {
    var patient: ExtractedPatientInfo = ExtractedPatientInfo()
    var provider: ExtractedProviderInfo = ExtractedProviderInfo()
    var procedures: [ExtractedProcedureLine] = []
    var billNumber: String = ""
    var billDate: Date = Date()
    var dueDate: Date?
    var totalCharges: Double = 0
    var insurancePaid: Double = 0
    var adjustments: Double = 0
    var amountDue: Double = 0
    var rawText: String = ""
}

// MARK: - Bill Document Scanner View

struct BillDocumentScanner: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var patientDataService: PatientDataService
    @EnvironmentObject var appState: AppState
    
    // Callback when scan is complete
    let onScanComplete: (ExtractedBillData) -> Void
    
    @State private var selectedImage: UIImage?
    @State private var showingPhotoPicker = false
    @State private var showingFilePicker = false
    @State private var showingCamera = false
    
    @State private var isProcessing = false
    @State private var processingStep = ""
    @State private var extractedData = ExtractedBillData()
    @State private var showingReview = false
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if selectedImage != nil {
                    // Processing or review
                    if showingReview {
                        BillDataReviewView(
                            extractedData: $extractedData,
                            onConfirm: {
                                onScanComplete(extractedData)
                                dismiss()
                            },
                            onRescan: {
                                selectedImage = nil
                                showingReview = false
                                extractedData = ExtractedBillData()
                            }
                        )
                        .environmentObject(appState)
                    } else {
                        // Show image while processing
                        processingView
                    }
                } else {
                    // Source selection
                    sourceSelectionView
                }
            }
            .navigationTitle("Scan Bill")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .fullScreenCover(isPresented: $showingCamera) {
                SmartDocumentScanner(capturedImage: $selectedImage)
            }
            .sheet(isPresented: $showingPhotoPicker) {
                PhotoPicker(image: $selectedImage)
            }
            .sheet(isPresented: $showingFilePicker) {
                FilePicker(image: $selectedImage)
            }
            .onChange(of: selectedImage) { _, newImage in
                if newImage != nil {
                    processImage()
                }
            }
            .alert("Scan Error", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }
    
    // MARK: - Source Selection View
    
    private var sourceSelectionView: some View {
        VStack(spacing: 30) {
            Spacer()
            
            Image(systemName: "doc.text.viewfinder")
                .font(.system(size: 80))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.accentColor, .accentColor.opacity(0.6)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            VStack(spacing: 8) {
                Text("Scan Medical Bill")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Extract patient, provider, and procedure details")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            VStack(spacing: 16) {
                // Smart Camera (highlighted)
                Button {
                    showingCamera = true
                } label: {
                    HStack(spacing: 16) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color("BrandCyan"))
                                .frame(width: 50, height: 50)
                            Image(systemName: "viewfinder")
                                .font(.title2)
                                .foregroundColor(.white)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Smart Scan")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                
                                Text("RECOMMENDED")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.green)
                                    .foregroundColor(.white)
                                    .cornerRadius(4)
                            }
                            Text("Auto-align & capture with guides")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color("BrandCyan").opacity(0.1))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color("BrandCyan"), lineWidth: 2)
                    )
                }
                .buttonStyle(.plain)
                
                // Photo Library
                SourceButton(
                    icon: "photo.on.rectangle",
                    title: "Photo Library",
                    subtitle: "Select from saved photos",
                    color: .green
                ) {
                    showingPhotoPicker = true
                }
                
                // Files (PDF/PNG)
                SourceButton(
                    icon: "folder.fill",
                    title: "Files",
                    subtitle: "Import PDF or image files",
                    color: .orange
                ) {
                    showingFilePicker = true
                }
            }
            .padding(.horizontal)
            
            Spacer()
            
            // Tips
            VStack(alignment: .leading, spacing: 12) {
                Text("Smart Scan features:")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                
                ScanTip(icon: "viewfinder", text: "Alignment guides for perfect capture")
                ScanTip(icon: "checkmark.circle", text: "Auto-capture when aligned")
                ScanTip(icon: "wand.and.stars", text: "Automatic image enhancement")
            }
            .padding()
            .background(Color("BrandNavy"))
            .cornerRadius(12)
            .padding()
        }
    }
    
    // MARK: - Processing View
    
    private var processingView: some View {
        VStack(spacing: 30) {
            if let image = selectedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 300)
                    .cornerRadius(12)
                    .shadow(radius: 5)
                    .padding()
            }
            
            VStack(spacing: 16) {
                LoadingShieldView(size: 80)
                
                Text(processingStep)
                    .font(.headline)
                    .foregroundColor(.secondary)
            }
        }
        .loadingOverlay(isLoading: isProcessing, message: processingStep, style: .ring)
    }
    
    // MARK: - Process Image
    
    private func processImage() {
        guard let image = selectedImage else { return }
        
        isProcessing = true
        processingStep = "Analyzing document..."
        
        Task {
            do {
                // Step 1: Extract all text
                processingStep = "Extracting text..."
                let fullText = try await extractText(from: image)
                
                await MainActor.run {
                    extractedData.rawText = fullText
                }
                
                // Step 2: Parse patient info
                processingStep = "Finding patient information..."
                let patient = parsePatientInfo(from: fullText)
                
                // Step 3: Parse provider info
                processingStep = "Finding provider information..."
                let provider = parseProviderInfo(from: fullText)
                
                // Step 4: Parse procedure lines
                processingStep = "Extracting procedures..."
                var procedures = parseProcedureLines(from: fullText)
                
                // Step 5: Match with database and get cost ranges
                processingStep = "Matching procedure codes..."
                procedures = matchProcedureCodes(procedures)
                
                // Step 6: Parse financial summary
                processingStep = "Calculating totals..."
                let (total, insurance, adjustments, due) = parseFinancials(from: fullText)
                
                await MainActor.run {
                    extractedData.patient = patient
                    extractedData.provider = provider
                    extractedData.procedures = procedures
                    extractedData.totalCharges = total
                    extractedData.insurancePaid = insurance
                    extractedData.adjustments = adjustments
                    extractedData.amountDue = due
                    
                    isProcessing = false
                    showingReview = true
                }
                
            } catch {
                await MainActor.run {
                    isProcessing = false
                    errorMessage = "Failed to process image: \(error.localizedDescription)"
                }
            }
        }
    }
    
    // MARK: - Text Extraction
    
    private func extractText(from image: UIImage) async throws -> String {
        guard let cgImage = image.cgImage else {
            throw NSError(domain: "BillScanner", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid image"])
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: "")
                    return
                }
                
                let text = observations.compactMap { observation in
                    observation.topCandidates(1).first?.string
                }.joined(separator: "\n")
                
                continuation.resume(returning: text)
            }
            
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    // MARK: - Parsing Functions
    
    private func parsePatientInfo(from text: String) -> ExtractedPatientInfo {
        var info = ExtractedPatientInfo()
        let lines = text.components(separatedBy: .newlines)

        // ── valueAfterLabel ──────────────────────────────────────────────────
        // Extracts the value after a label on the same line, stopping at the
        // NEXT inline label (word + colon) to handle two-column bill layouts.
        //
        // Example:  "Patient:  Richard B. Patel      Insurance:  Oscar Health"
        //            label="Patient"  ->  "Richard B. Patel"   (stops at "Insurance:")
        func valueAfterLabel(_ line: String, _ labelPattern: String) -> String? {
            guard let regex = try? NSRegularExpression(pattern: labelPattern, options: .caseInsensitive),
                  let match = regex.firstMatch(in: line, options: [],
                                               range: NSRange(line.startIndex..., in: line)),
                  match.numberOfRanges > 1,
                  let vRange = Range(match.range(at: 1), in: line) else { return nil }
            let raw = String(line[vRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            // Strip any trailing inline label: two or more spaces then Word:
            if let nextLabel = raw.range(of: #"\s{2,}\w[\w\s]*\s*:"#,
                                         options: .regularExpression) {
                let val = String(raw[raw.startIndex..<nextLabel.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return val.isEmpty ? nil : val
            }
            return raw.isEmpty ? nil : raw
        }

        // ── Tag definitions ──────────────────────────────────────────────────
        // Each entry: (keyPath, [label regex patterns])
        // The capture group must be group 1 and should be (.+) — the
        // trailing-label stripping above handles truncation.
        typealias TagDef = (WritableKeyPath<ExtractedPatientInfo, String>, [String])
        let tagDefs: [TagDef] = [
            (\.name, [
                #"(?i)patient\s*name\s*[:]\s*(.+)"#,
                #"(?i)(?<![a-z])patient\s*[:]\s*(.+)"#
            ]),
            (\.accountNumber, [
                #"(?i)account\s*(?:#|no\.?|number)?\s*[:]\s*(.+)"#,
                #"(?i)acct\s*(?:#|no\.?)?\s*[:]\s*(.+)"#
            ]),
            (\.insurance, [
                #"(?i)insurance\s*[:]\s*(.+)"#,
                #"(?i)(?:carrier|payer|plan|ins)\s*[:]\s*(.+)"#
            ]),
            (\.policyNumber, [
                #"(?i)policy\s*(?:#|no\.?|number)?\s*[:]\s*(.+)"#
            ]),
            (\.mrn, [
                #"(?i)mrn\s*[:]\s*(.+)"#,
                #"(?i)medical\s*record\s*(?:#|no\.?|number)?\s*[:]\s*(.+)"#
            ]),
            (\.dateOfService, [
                #"(?i)date\s*of\s*service\s*[:]\s*(.+)"#,
                #"(?i)service\s*date\s*[:]\s*(.+)"#,
                #"(?i)\bdos\b\s*[:]\s*(.+)"#,
                #"(?i)visit\s*date\s*[:]\s*(.+)"#
            ]),
            (\.dischargeDate, [
                #"(?i)discharge\s*date\s*[:]\s*(.+)"#
            ]),
            (\.dateOfBirth, [
                #"(?i)date\s*of\s*birth\s*[:]\s*(.+)"#,
                #"(?i)\bdob\b\s*[:]\s*(.+)"#,
                #"(?i)d\.o\.b\.?\s*[:]\s*(.+)"#
            ])
        ]

        var tagConsumedLines = Set<Int>()

        for (lineIdx, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            for (keyPath, patterns) in tagDefs {
                guard info[keyPath: keyPath].isEmpty else { continue }
                for pattern in patterns {
                    if let val = valueAfterLabel(trimmed, pattern) {
                        // Final sanity: reject if captured value is empty or is itself a label
                        let isJustLabel = val.hasSuffix(":") || val.count < 2
                        if !isJustLabel {
                            info[keyPath: keyPath] = val
                            tagConsumedLines.insert(lineIdx)
                            break
                        }
                    }
                }
            }
        }

        // ── Pass 2: pattern-based fallbacks for fields not yet populated ────
        let phonePattern   = #"\(?\d{3}\)?[-.\s]?\d{3}[-.\s]?\d{4}"#
        let zipPattern     = #"\b\d{5}(-\d{4})?\b"#
        let statePattern   = #"\b(AL|AK|AZ|AR|CA|CO|CT|DE|FL|GA|HI|ID|IL|IN|IA|KS|KY|LA|ME|MD|MA|MI|MN|MS|MO|MT|NE|NV|NH|NJ|NM|NY|NC|ND|OH|OK|OR|PA|RI|SC|SD|TN|TX|UT|VT|VA|WA|WV|WI|WY)\b"#

        var inPatientSection = false
        for (lineIdx, line) in lines.enumerated() {
            if tagConsumedLines.contains(lineIdx) { continue }
            let lowercased = line.lowercased()

            if lowercased.contains("patient") &&
               (lowercased.contains("name") || lowercased.contains("info")) {
                inPatientSection = true
            }

            // Phone
            if info.phone.isEmpty,
               let m = line.range(of: phonePattern, options: .regularExpression),
               (inPatientSection || lineIdx < 15) {
                info.phone = String(line[m])
            }

            // State
            if info.state.isEmpty,
               let m = line.range(of: statePattern, options: .regularExpression) {
                info.state = String(line[m])
            }

            // ZIP
            if info.zipCode.isEmpty,
               let m = line.range(of: zipPattern, options: .regularExpression) {
                info.zipCode = String(line[m])
            }

            // Address heuristic
            if info.address.isEmpty && inPatientSection {
                let addressIndicators = ["street","ave","avenue","road","rd","blvd","dr ","lane","ln","way","court","ct","place","pl"]
                if addressIndicators.contains(where: { lowercased.contains($0) }) ||
                   line.range(of: #"^\d+\s+\w+"#, options: .regularExpression) != nil {
                    info.address = line.trimmingCharacters(in: .whitespaces)
                }
            }
        }

        return info
    }

    private func parseProviderInfo(from text: String) -> ExtractedProviderInfo {
        var info = ExtractedProviderInfo()
        let lines = text.components(separatedBy: .newlines)
        
        let phonePattern = #"\(?\d{3}\)?[-.\s]?\d{3}[-.\s]?\d{4}"#
        let npiPattern = #"(?i)(?:npi|national\s*provider)[\s:#]*(\d{10})"#
        let taxIdPattern = #"(?i)(?:tax\s*id|ein|tin)[\s:#]*(\d{2}-?\d{7})"#
        let zipPattern = #"\b\d{5}(-\d{4})?\b"#
        let statePattern = #"\b(AL|AK|AZ|AR|CA|CO|CT|DE|FL|GA|HI|ID|IL|IN|IA|KS|KY|LA|ME|MD|MA|MI|MN|MS|MO|MT|NE|NV|NH|NJ|NM|NY|NC|ND|OH|OK|OR|PA|RI|SC|SD|TN|TX|UT|VT|VA|WA|WV|WI|WY)\b"#
        
        // Provider/facility indicators
        let facilityKeywords = ["hospital", "medical center", "clinic", "health", "healthcare", "physicians", "associates", "practice", "center"]
        
        for (index, line) in lines.enumerated() {
            let lowercased = line.lowercased()
            
            // NPI
            if let match = line.range(of: npiPattern, options: .regularExpression) {
                let npiLine = String(line[match])
                if let numMatch = npiLine.range(of: #"\d{10}"#, options: .regularExpression) {
                    info.npi = String(npiLine[numMatch])
                }
            }
            
            // Tax ID
            if let match = line.range(of: taxIdPattern, options: .regularExpression) {
                let taxLine = String(line[match])
                if let numMatch = taxLine.range(of: #"\d{2}-?\d{7}"#, options: .regularExpression) {
                    info.taxId = String(taxLine[numMatch])
                }
            }
            
            // Phone (usually in first few lines for provider)
            if let match = line.range(of: phonePattern, options: .regularExpression) {
                let phone = String(line[match])
                if index < 10 && info.phone.isEmpty {
                    info.phone = phone
                }
            }
            
            // Facility name detection
            for keyword in facilityKeywords {
                if lowercased.contains(keyword) && info.facilityName.isEmpty {
                    info.facilityName = line.trimmingCharacters(in: .whitespaces)
                    break
                }
            }
            
            // Provider name (Dr., MD, DO, etc.)
            if lowercased.contains("dr.") || lowercased.contains("md") || lowercased.contains("do") ||
                lowercased.contains("physician") || lowercased.contains("provider:") {
                if info.name.isEmpty {
                    info.name = line.replacingOccurrences(of: "Provider:", with: "", options: .caseInsensitive)
                        .trimmingCharacters(in: .whitespaces)
                }
            }
            
            // State
            if let match = line.range(of: statePattern, options: .regularExpression) {
                if info.state.isEmpty && index < 15 {
                    info.state = String(line[match])
                }
            }
            
            // Zip
            if let match = line.range(of: zipPattern, options: .regularExpression) {
                if info.zipCode.isEmpty && index < 15 {
                    info.zipCode = String(line[match])
                }
            }
        }
        
        // First line is often the facility name
        if info.facilityName.isEmpty && !lines.isEmpty {
            let firstLine = lines[0].trimmingCharacters(in: .whitespaces)
            if !firstLine.isEmpty && firstLine.count > 3 {
                info.facilityName = firstLine
            }
        }
        
        return info
    }
    
    private func parseProcedureLines(from text: String) -> [ExtractedProcedureLine] {
        var procedures: [ExtractedProcedureLine] = []
        let lines = text.components(separatedBy: .newlines)
        
        // Code patterns - more comprehensive
        // CPT: 5 digits (e.g., 99213)
        let cptPattern = #"\b(\d{5})\b"#
        // HCPCS: Letter + 4 digits (e.g., J1234, G0101)
        let hcpcsPattern = #"\b([A-Z]\d{4})\b"#
        // ICD-10: Letter + digits, optionally with decimal (e.g., Z00.00, M54.5, E11.9)
        let icd10Pattern = #"\b([A-TV-Z]\d{2,3}(?:\.\d{1,4})?)\b"#
        // ICD-10-PCS: 7 alphanumeric (e.g., 0BJ08ZZ) - procedure codes
        let icd10PcsPattern = #"\b(\d[A-Z0-9]{6})\b"#
        
        // Amount patterns - various formats
        let amountPattern = #"\$?\s*(\d{1,3}(?:,\d{3})*(?:\.\d{2})?)"#
        // Date pattern
        let datePattern = #"\d{1,2}[/-]\d{1,2}[/-]\d{2,4}"#
        
        // Payment-related keywords to identify payment columns vs charges
        let paymentKeywords = ["paid", "payment", "insurance", "adjust", "discount", "allowed", "copay", "coinsurance", "deductible", "balance", "due", "owed"]
        
        // Track codes we've already processed to avoid duplicates
        var processedCodes = Set<String>()
        
        for line in lines {
            let lowercaseLine = line.lowercased()
            
            // Skip header lines
            if isHeaderLine(line) { continue }
            
            // Extract ALL codes from this line (could have multiple)
            var codesFound: [(code: String, type: CodeType, range: Range<String.Index>)] = []
            
            // Find CPT codes
            if let regex = try? NSRegularExpression(pattern: cptPattern, options: []) {
                let nsRange = NSRange(line.startIndex..., in: line)
                for match in regex.matches(in: line, options: [], range: nsRange) {
                    if let range = Range(match.range(at: 1), in: line) {
                        let code = String(line[range])
                        // Verify it's likely a CPT code (not just any 5 digits like a zip code or date)
                        if isCPTCode(code, in: line) {
                            codesFound.append((code, .cpt, range))
                        }
                    }
                }
            }
            
            // Find HCPCS codes
            if let regex = try? NSRegularExpression(pattern: hcpcsPattern, options: []) {
                let nsRange = NSRange(line.startIndex..., in: line)
                for match in regex.matches(in: line, options: [], range: nsRange) {
                    if let range = Range(match.range(at: 1), in: line) {
                        let code = String(line[range])
                        codesFound.append((code, .hcpcs, range))
                    }
                }
            }
            
            // Find ICD-10 diagnosis codes
            if let regex = try? NSRegularExpression(pattern: icd10Pattern, options: []) {
                let nsRange = NSRange(line.startIndex..., in: line)
                for match in regex.matches(in: line, options: [], range: nsRange) {
                    if let range = Range(match.range(at: 1), in: line) {
                        let code = String(line[range])
                        // Verify it's likely an ICD-10 code
                        if isICD10Code(code) {
                            codesFound.append((code, .icd10, range))
                        }
                    }
                }
            }
            
            // Find ICD-10-PCS codes
            if let regex = try? NSRegularExpression(pattern: icd10PcsPattern, options: []) {
                let nsRange = NSRange(line.startIndex..., in: line)
                for match in regex.matches(in: line, options: [], range: nsRange) {
                    if let range = Range(match.range(at: 1), in: line) {
                        let code = String(line[range])
                        codesFound.append((code, .icd10pcs, range))
                    }
                }
            }
            
            // Skip if no codes found
            if codesFound.isEmpty { continue }
            
            // Extract all amounts from the line
            var amounts: [(value: Double, range: Range<String.Index>, isPayment: Bool)] = []
            if let regex = try? NSRegularExpression(pattern: amountPattern, options: []) {
                let nsRange = NSRange(line.startIndex..., in: line)
                for match in regex.matches(in: line, options: [], range: nsRange) {
                    if let range = Range(match.range(at: 1), in: line) {
                        let amountStr = String(line[range])
                            .replacingOccurrences(of: ",", with: "")
                        if let value = Double(amountStr) {
                            // Check if this amount is preceded by payment-related keywords
                            let beforeAmount = String(line[line.startIndex..<range.lowerBound]).lowercased()
                            let isPayment = paymentKeywords.contains { beforeAmount.contains($0) }
                            amounts.append((value, range, isPayment))
                        }
                    }
                }
            }
            
            // Extract date from line
            var serviceDate: Date?
            if let dateMatch = line.range(of: datePattern, options: .regularExpression) {
                serviceDate = parseDate(String(line[dateMatch]))
            }
            
            // Separate procedure codes from diagnosis codes
            let procedureCodes = codesFound.filter { $0.type == .cpt || $0.type == .hcpcs || $0.type == .icd10pcs }
            let diagnosisCodes = codesFound.filter { $0.type == .icd10 }
            
            // If we have procedure codes, create procedure lines
            if !procedureCodes.isEmpty {
                for procCode in procedureCodes {
                    // Skip if already processed
                    if processedCodes.contains(procCode.code) { continue }
                    processedCodes.insert(procCode.code)
                    
                    var procedure = ExtractedProcedureLine()
                    procedure.code = procCode.code
                    
                    // Add any diagnosis codes found on this line
                    procedure.diagnosisCodes = diagnosisCodes.map { $0.code }
                    
                    // Find the charge amount (first non-payment amount, or largest)
                    let chargeAmounts = amounts.filter { !$0.isPayment }
                    if let chargeAmount = chargeAmounts.first {
                        procedure.totalCost = chargeAmount.value
                    } else if let firstAmount = amounts.first {
                        procedure.totalCost = firstAmount.value
                    }
                    
                    // If multiple charge amounts, first might be unit cost
                    if chargeAmounts.count > 1 {
                        procedure.unitCost = chargeAmounts[0].value
                        procedure.totalCost = chargeAmounts[1].value
                    }
                    
                    // Extract description
                    procedure.description = extractDescription(from: line, excludingCode: procCode.code, amounts: amounts.map { String(format: "%.2f", $0.value) })
                    
                    // Set date
                    if let date = serviceDate {
                        procedure.serviceDate = date
                    }
                    
                    procedures.append(procedure)
                }
            } else if !diagnosisCodes.isEmpty {
                // Line only has diagnosis codes - might still be a billable line
                // Some bills list diagnosis codes with charges
                for diagCode in diagnosisCodes {
                    if processedCodes.contains(diagCode.code) { continue }
                    
                    // Only create a procedure line if there's an amount
                    let chargeAmounts = amounts.filter { !$0.isPayment }
                    if let chargeAmount = chargeAmounts.first {
                        processedCodes.insert(diagCode.code)
                        
                        var procedure = ExtractedProcedureLine()
                        procedure.code = diagCode.code
                        procedure.totalCost = chargeAmount.value
                        procedure.description = extractDescription(from: line, excludingCode: diagCode.code, amounts: amounts.map { String(format: "%.2f", $0.value) })
                        
                        if let date = serviceDate {
                            procedure.serviceDate = date
                        }
                        
                        procedures.append(procedure)
                    }
                }
            }
        }
        
        // Also look for codes embedded in parentheses within descriptions
        // e.g., "Office Visit (99213) - $150.00"
        for line in lines {
            let embeddedPattern = #"\((\d{5}|[A-Z]\d{4})\)"#
            if let regex = try? NSRegularExpression(pattern: embeddedPattern, options: []) {
                let nsRange = NSRange(line.startIndex..., in: line)
                for match in regex.matches(in: line, options: [], range: nsRange) {
                    if let codeRange = Range(match.range(at: 1), in: line) {
                        let code = String(line[codeRange])
                        if processedCodes.contains(code) { continue }
                        processedCodes.insert(code)
                        
                        var procedure = ExtractedProcedureLine()
                        procedure.code = code
                        
                        // Extract amount
                        if let amountRegex = try? NSRegularExpression(pattern: amountPattern, options: []) {
                            let amounts = amountRegex.matches(in: line, options: [], range: nsRange)
                            if let firstAmount = amounts.first,
                               let range = Range(firstAmount.range(at: 1), in: line) {
                                let amountStr = String(line[range]).replacingOccurrences(of: ",", with: "")
                                procedure.totalCost = Double(amountStr) ?? 0
                            }
                        }
                        
                        // Description is text before the parentheses
                        if let parenRange = line.range(of: "(\(code))") {
                            procedure.description = String(line[line.startIndex..<parenRange.lowerBound])
                                .trimmingCharacters(in: .whitespaces)
                                .trimmingCharacters(in: CharacterSet(charactersIn: "-:"))
                                .trimmingCharacters(in: .whitespaces)
                        }
                        
                        procedures.append(procedure)
                    }
                }
            }
        }
        
        return procedures
    }
    
    // MARK: - Helper Enums and Functions for Parsing
    
    private enum CodeType {
        case cpt, hcpcs, icd10, icd10pcs
    }
    
    private func isHeaderLine(_ line: String) -> Bool {
        let headerKeywords = ["description", "service", "procedure", "code", "date", "charge", "amount", "qty", "quantity", "units", "total"]
        let lowercased = line.lowercased()
        let matchCount = headerKeywords.filter { lowercased.contains($0) }.count
        return matchCount >= 2 // If multiple header keywords, likely a header row
    }
    
    private func isCPTCode(_ code: String, in line: String) -> Bool {
        // CPT codes are 5 digits, but so are zip codes
        // Check if this looks like part of an address (has state abbreviation nearby)
        let statePattern = #"\b[A-Z]{2}\s+\d{5}\b"#
        if line.range(of: statePattern, options: .regularExpression) != nil {
            // This might be a zip code - check if the code is immediately after a state
            if let stateMatch = line.range(of: #"\b[A-Z]{2}\s+"# + code, options: .regularExpression) {
                return false // It's likely a zip code
            }
        }
        
        // CPT codes typically start with certain ranges
        // 00100-01999: Anesthesia
        // 10021-69990: Surgery
        // 70010-79999: Radiology
        // 80047-89398: Pathology/Lab
        // 90281-99607: Medicine
        // E/M codes: 99201-99499
        if let codeInt = Int(code) {
            // Valid CPT ranges
            if (codeInt >= 100 && codeInt <= 1999) ||      // Anesthesia
                (codeInt >= 10021 && codeInt <= 69990) ||   // Surgery
                (codeInt >= 70010 && codeInt <= 79999) ||   // Radiology
                (codeInt >= 80047 && codeInt <= 89398) ||   // Lab
                (codeInt >= 90281 && codeInt <= 99607) {    // Medicine
                return true
            }
        }
        
        return true // Default to accepting it
    }
    
    private func isICD10Code(_ code: String) -> Bool {
        // ICD-10 codes start with a letter (except U), followed by digits
        // They can have a decimal point
        guard let firstChar = code.first else { return false }
        
        // Valid starting letters for ICD-10
        let validStarts: Set<Character> = Set("ABCDEFGHIJKLMNOPQRSTVWXYZ")
        if !validStarts.contains(firstChar) { return false }
        
        // Must be at least 3 characters (e.g., A00)
        if code.count < 3 { return false }
        
        // Filter out things that look like codes but aren't (e.g., "PO Box", "ID", etc.)
        let uppercased = code.uppercased()
        let falsePositives = ["PO", "ID", "MD", "DO", "PA", "NP", "RN", "DR", "MR", "MS", "FL", "CA", "TX", "NY"]
        if falsePositives.contains(uppercased.prefix(2).description) && !code.contains(".") {
            return false
        }
        
        return true
    }
    
    private func parseDate(_ dateStr: String) -> Date? {
        let formatters = [
            "MM/dd/yyyy",
            "M/d/yyyy",
            "MM-dd-yyyy",
            "M-d-yyyy",
            "MM/dd/yy",
            "M/d/yy"
        ]
        
        for format in formatters {
            let formatter = DateFormatter()
            formatter.dateFormat = format
            if let date = formatter.date(from: dateStr) {
                return date
            }
        }
        return nil
    }
    
    private func extractDescription(from line: String, excludingCode code: String, amounts: [String]) -> String {
        var description = line
        
        // Remove the code
        description = description.replacingOccurrences(of: code, with: "")
        
        // Remove code in parentheses
        description = description.replacingOccurrences(of: "(\(code))", with: "")
        
        // Remove amounts
        for amount in amounts {
            description = description.replacingOccurrences(of: "$\(amount)", with: "")
            description = description.replacingOccurrences(of: amount, with: "")
        }
        
        // Remove dates
        let datePattern = #"\d{1,2}[/-]\d{1,2}[/-]\d{2,4}"#
        if let regex = try? NSRegularExpression(pattern: datePattern, options: []) {
            description = regex.stringByReplacingMatches(in: description, options: [], range: NSRange(description.startIndex..., in: description), withTemplate: "")
        }
        
        // Remove common column separators and clean up
        description = description
            .replacingOccurrences(of: "|", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-:,"))
            .trimmingCharacters(in: .whitespaces)
        
        // Remove payment-related suffixes
        let paymentPattern = #"(?i)(paid|payment|insurance|adjust|discount|allowed|copay|balance|due).*$"#
        if let regex = try? NSRegularExpression(pattern: paymentPattern, options: []) {
            description = regex.stringByReplacingMatches(in: description, options: [], range: NSRange(description.startIndex..., in: description), withTemplate: "")
        }
        
        return description.trimmingCharacters(in: .whitespaces)
    }
    
    private func matchProcedureCodes(_ procedures: [ExtractedProcedureLine]) -> [ExtractedProcedureLine] {
        var matched = procedures
        
        for (index, procedure) in matched.enumerated() {
            if let match = appState.cloudKitService.lookupCode(procedure.code) {
                matched[index].matchedCode = match
                matched[index].normalCostLow = match.priceLow
                matched[index].normalCostHigh = match.priceHigh
                matched[index].normalCostAverage = match.priceAverage
                
                // Use database description if scanned one is poor
                if matched[index].description.count < 5 {
                    matched[index].description = match.shortDescription
                }
            }
        }
        
        return matched
    }
    
    private func parseFinancials(from text: String) -> (Double, Double, Double, Double) {
        var total: Double = 0
        var insurance: Double = 0
        var adjustments: Double = 0
        var due: Double = 0
        
        let lines = text.components(separatedBy: .newlines)
        let amountPattern = #"\$?\s*\d{1,3}(?:,\d{3})*(?:\.\d{2})?"#
        
        for line in lines {
            let lowercased = line.lowercased()
            
            guard let amountMatch = line.range(of: amountPattern, options: .regularExpression) else { continue }
            let amountStr = String(line[amountMatch])
                .replacingOccurrences(of: "$", with: "")
                .replacingOccurrences(of: ",", with: "")
                .trimmingCharacters(in: .whitespaces)
            guard let amount = Double(amountStr) else { continue }
            
            if lowercased.contains("total charge") || lowercased.contains("total amount") ||
                (lowercased.contains("total") && !lowercased.contains("due") && !lowercased.contains("paid")) {
                total = amount
            } else if lowercased.contains("insurance paid") || lowercased.contains("ins paid") ||
                        lowercased.contains("insurance payment") {
                insurance = amount
            } else if lowercased.contains("adjustment") || lowercased.contains("discount") ||
                        lowercased.contains("write off") {
                adjustments = amount
            } else if lowercased.contains("amount due") || lowercased.contains("balance due") ||
                        lowercased.contains("patient responsibility") || lowercased.contains("you owe") ||
                        lowercased.contains("please pay") {
                due = amount
            }
        }
        
        return (total, insurance, adjustments, due)
    }
}

// MARK: - Source Button

struct SourceButton: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(.white)
                    .frame(width: 50, height: 50)
                    .background(color)
                    .cornerRadius(12)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color("BrandNavy"))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Scan Tip

struct ScanTip: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(.accentColor)
                .frame(width: 20)
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Photo Picker

struct PhotoPicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PhotoPicker
        
        init(_ parent: PhotoPicker) {
            self.parent = parent
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.dismiss()
            
            guard let result = results.first else { return }
            
            result.itemProvider.loadObject(ofClass: UIImage.self) { [weak self] object, error in
                if let image = object as? UIImage {
                    DispatchQueue.main.async {
                        self?.parent.image = image
                    }
                }
            }
        }
    }
}

// MARK: - File Picker

struct FilePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let types: [UTType] = [.image, .pdf, .png, .jpeg]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: FilePicker
        
        init(_ parent: FilePicker) {
            self.parent = parent
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            
            // Start security-scoped access
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }
            
            if url.pathExtension.lowercased() == "pdf" {
                // Convert PDF to image
                if let image = pdfToImage(url: url) {
                    DispatchQueue.main.async {
                        self.parent.image = image
                    }
                }
            } else {
                // Load image
                if let data = try? Data(contentsOf: url),
                   let image = UIImage(data: data) {
                    DispatchQueue.main.async {
                        self.parent.image = image
                    }
                }
            }
        }
        
        private func pdfToImage(url: URL) -> UIImage? {
            guard let document = CGPDFDocument(url as CFURL),
                  let page = document.page(at: 1) else { return nil }
            
            let pageRect = page.getBoxRect(.mediaBox)
            let scale: CGFloat = 2.0
            let size = CGSize(width: pageRect.width * scale, height: pageRect.height * scale)
            
            UIGraphicsBeginImageContextWithOptions(size, false, 0)
            guard let context = UIGraphicsGetCurrentContext() else { return nil }
            
            context.setFillColor(UIColor.white.cgColor)
            context.fill(CGRect(origin: .zero, size: size))
            
            context.translateBy(x: 0, y: size.height)
            context.scaleBy(x: scale, y: -scale)
            context.drawPDFPage(page)
            
            let image = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            
            return image
        }
    }
}

// MARK: - Bill Data Review View

struct BillDataReviewView: View {
    @Binding var extractedData: ExtractedBillData
    @EnvironmentObject var appState: AppState
    
    let onConfirm: () -> Void
    let onRescan: () -> Void
    
    @State private var selectedSection = 0
    
    var body: some View {
        VStack(spacing: 0) {
            // Section picker
            Picker("Section", selection: $selectedSection) {
                Text("Patient").tag(0)
                Text("Provider").tag(1)
                Text("Procedures").tag(2)
                Text("Summary").tag(3)
            }
            .pickerStyle(.segmented)
            .padding()
            
            // Content
            ScrollView {
                switch selectedSection {
                case 0:
                    patientSection
                case 1:
                    providerSection
                case 2:
                    proceduresSection
                case 3:
                    summarySection
                default:
                    EmptyView()
                }
            }
            
            // Actions
            HStack(spacing: 16) {
                Button {
                    onRescan()
                } label: {
                    HStack {
                        Image(systemName: "arrow.counterclockwise")
                        Text("Rescan")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color("BrandNavy"))
                    .cornerRadius(12)
                }
                
                Button {
                    onConfirm()
                } label: {
                    HStack {
                        Image(systemName: "checkmark")
                        Text("Confirm")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .foregroundColor(.white)
                    .background(Color.accentColor)
                    .cornerRadius(12)
                }
            }
            .padding()
        }
    }
    
    // MARK: - Patient Section
    
    private var patientSection: some View {
        VStack(spacing: 16) {
            EditableField(label: "Name", text: $extractedData.patient.name, icon: "person")
            EditableField(label: "Account #", text: $extractedData.patient.accountNumber, icon: "number.circle")
            EditableField(label: "MRN", text: $extractedData.patient.mrn, icon: "cross.case")
            EditableField(label: "Date of Service", text: $extractedData.patient.dateOfService, icon: "calendar")
            EditableField(label: "Discharge Date", text: $extractedData.patient.dischargeDate, icon: "calendar.badge.checkmark")
            EditableField(label: "Insurance", text: $extractedData.patient.insurance, icon: "shield")
            EditableField(label: "Policy #", text: $extractedData.patient.policyNumber, icon: "doc.badge.gearshape")
            EditableField(label: "Date of Birth", text: $extractedData.patient.dateOfBirth, icon: "gift")
            EditableField(label: "Phone", text: $extractedData.patient.phone, icon: "phone")
            EditableField(label: "Address", text: $extractedData.patient.address, icon: "house")

            HStack(spacing: 12) {
                EditableField(label: "City", text: $extractedData.patient.city, icon: "building.2")
                EditableField(label: "State", text: $extractedData.patient.state, icon: "map")
                    .frame(width: 80)
                EditableField(label: "ZIP", text: $extractedData.patient.zipCode, icon: "number")
                    .frame(width: 100)
            }
        }
        .padding()
    }
    
    // MARK: - Provider Section
    
    private var providerSection: some View {
        VStack(spacing: 16) {
            EditableField(label: "Facility Name", text: $extractedData.provider.facilityName, icon: "building")
            EditableField(label: "Provider Name", text: $extractedData.provider.name, icon: "person")
            EditableField(label: "Address", text: $extractedData.provider.address, icon: "house")
            
            HStack(spacing: 12) {
                EditableField(label: "City", text: $extractedData.provider.city, icon: "building.2")
                EditableField(label: "State", text: $extractedData.provider.state, icon: "map")
                    .frame(width: 80)
                EditableField(label: "ZIP", text: $extractedData.provider.zipCode, icon: "number")
                    .frame(width: 100)
            }
            
            EditableField(label: "Phone", text: $extractedData.provider.phone, icon: "phone")
            EditableField(label: "NPI", text: $extractedData.provider.npi, icon: "number.circle")
            EditableField(label: "Tax ID", text: $extractedData.provider.taxId, icon: "doc.text")
        }
        .padding()
    }
    
    // MARK: - Procedures Section
    
    private var proceduresSection: some View {
        VStack(spacing: 16) {
            if extractedData.procedures.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 50))
                        .foregroundColor(.secondary)
                    Text("No procedures detected")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Button("Add Procedure") {
                        extractedData.procedures.append(ExtractedProcedureLine())
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity)
                .padding(40)
            } else {
                ForEach($extractedData.procedures) { $procedure in
                    ProcedureEditCard(procedure: $procedure)
                }
                
                Button {
                    extractedData.procedures.append(ExtractedProcedureLine())
                } label: {
                    HStack {
                        Image(systemName: "plus.circle")
                        Text("Add Procedure")
                    }
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
    }
    
    // MARK: - Summary Section
    
    private var summarySection: some View {
        VStack(spacing: 20) {
            // Financial Summary
            VStack(spacing: 12) {
                Text("Financial Summary")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                AmountEditField(label: "Total Charges", amount: $extractedData.totalCharges)
                AmountEditField(label: "Insurance Paid", amount: $extractedData.insurancePaid)
                AmountEditField(label: "Adjustments", amount: $extractedData.adjustments)
                
                Divider()
                
                HStack {
                    Text("Amount Due")
                        .fontWeight(.semibold)
                    Spacer()
                    Text(extractedData.amountDue, format: .currency(code: "USD"))
                        .fontWeight(.bold)
                        .foregroundColor(.orange)
                }
            }
            .padding()
            .background(Color("BrandNavy"))
            .cornerRadius(12)
            
            // Procedure totals
            if !extractedData.procedures.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Procedure Costs")
                        .font(.headline)
                    
                    ForEach(extractedData.procedures) { proc in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(proc.code)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.accentColor)
                                Text(proc.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            
                            Spacer()
                            
                            VStack(alignment: .trailing) {
                                Text(proc.totalCost, format: .currency(code: "USD"))
                                    .fontWeight(.medium)
                                
                                if proc.hasCostComparison {
                                    Text(proc.costStatus.label)
                                        .font(.caption2)
                                        .foregroundColor(proc.costStatus.color)
                                }
                            }
                        }
                    }
                }
                .padding()
                .background(Color("BrandNavy"))
                .cornerRadius(12)
            }
        }
        .padding()
    }
}

// MARK: - Editable Field

struct EditableField: View {
    let label: String
    @Binding var text: String
    let icon: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            
            HStack {
                Image(systemName: icon)
                    .foregroundColor(.secondary)
                    .frame(width: 24)
                
                TextField(label, text: $text)
            }
            .padding(12)
            .background(Color("BrandNavy"))
            .cornerRadius(8)
        }
    }
}

// MARK: - Amount Edit Field

struct AmountEditField: View {
    let label: String
    @Binding var amount: Double
    
    @State private var amountText: String = ""
    
    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            HStack {
                Text("$")
                TextField("0.00", text: $amountText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 100)
                    .onChange(of: amountText) { _, newValue in
                        if let value = Double(newValue) {
                            amount = value
                        }
                    }
            }
        }
        .onAppear {
            amountText = String(format: "%.2f", amount)
        }
    }
}

// MARK: - Procedure Edit Card

struct ProcedureEditCard: View {
    @Binding var procedure: ExtractedProcedureLine
    @State private var isExpanded = true
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            Button {
                withAnimation { isExpanded.toggle() }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(procedure.code.isEmpty ? "New Procedure" : procedure.code)
                                .font(.system(.headline, design: .monospaced))
                                .foregroundColor(.accentColor)
                            
                            if procedure.hasCostComparison {
                                Text(procedure.costStatus.label)
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(procedure.costStatus.color.opacity(0.2))
                                    .foregroundColor(procedure.costStatus.color)
                                    .cornerRadius(4)
                            }
                        }
                        
                        Text(procedure.description.isEmpty ? "No description" : procedure.description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    
                    Spacer()
                    
                    Text(procedure.totalCost, format: .currency(code: "USD"))
                        .fontWeight(.semibold)
                    
                    Image(systemName: "chevron.down")
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color("BrandNavy"))
            }
            .buttonStyle(.plain)
            
            // Expanded content
            if isExpanded {
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Code")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            TextField("Code", text: $procedure.code)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                        }
                        .frame(width: 100)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Description")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            TextField("Description", text: $procedure.description)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                    
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Quantity")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            TextField("Qty", value: $procedure.quantity, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .keyboardType(.numberPad)
                        }
                        .frame(width: 80)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Unit Cost")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            TextField("$0.00", value: $procedure.unitCost, format: .currency(code: "USD"))
                                .textFieldStyle(.roundedBorder)
                                .keyboardType(.decimalPad)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Total")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            TextField("$0.00", value: $procedure.totalCost, format: .currency(code: "USD"))
                                .textFieldStyle(.roundedBorder)
                                .keyboardType(.decimalPad)
                        }
                    }
                    
                    // Cost comparison
                    if procedure.hasCostComparison {
                        HStack {
                            Image(systemName: "chart.bar")
                                .foregroundColor(.secondary)
                            Text("Normal range:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("\(procedure.normalCostLow ?? 0, format: .currency(code: "USD")) – \(procedure.normalCostHigh ?? 0, format: .currency(code: "USD"))")
                                .font(.caption)
                                .fontWeight(.medium)
                            Spacer()
                        }
                        .padding(8)
                        .background(procedure.costStatus.color.opacity(0.1))
                        .cornerRadius(6)
                    }
                }
                .padding()
                .background(Color(.tertiarySystemBackground))
            }
        }
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator), lineWidth: 0.5)
        )
    }
}

// MARK: - Preview

#Preview {
    BillDocumentScanner { data in
        print("Scan complete: \(data)")
    }
    .environmentObject(AppState())
    .environmentObject(PatientDataService.shared)
}
