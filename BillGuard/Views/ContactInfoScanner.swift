//
//  ContactInfoScanner.swift
//  BillGuard
//
//  Reusable OCR scanner for extracting contact information
//  Used for both Provider and Patient data entry
//

import SwiftUI
import Vision
import PhotosUI
import VisionKit
import UniformTypeIdentifiers

// MARK: - Extracted Contact Info

struct ExtractedContactInfo: Equatable {
    var name: String = ""
    var firstName: String = ""
    var lastName: String = ""
    var organization: String = ""
    var address: String = ""
    var city: String = ""
    var state: String = ""
    var zipCode: String = ""
    var phone: String = ""
    var email: String = ""
    var fax: String = ""
    var npi: String = ""
    var website: String = ""
    var dateOfBirth: String = ""
    var accountNumber: String = ""  // For patient account/member ID
    var insurance: String = ""      // Insurance company/plan name
    var dateOfService: String = ""  // Date or Date of Service
    var notes: String = ""          // For coverage type, plan info, other text
    
    var isValid: Bool {
        !name.isEmpty || !firstName.isEmpty || !organization.isEmpty || !accountNumber.isEmpty
    }
    
    var fullName: String {
        if !name.isEmpty { return name }
        return [firstName, lastName].filter { !$0.isEmpty }.joined(separator: " ")
    }
}

// MARK: - Scan Mode

enum ContactScanMode {
    case provider
    case patient
    
    var title: String {
        switch self {
        case .provider: return "Scan Provider Info"
        case .patient: return "Scan Patient Info"
        }
    }
    
    var icon: String {
        switch self {
        case .provider: return "building.2"
        case .patient: return "person"
        }
    }
}

// MARK: - Contact Info Scanner View

struct ContactInfoScannerView: View {
    @Environment(\.dismiss) private var dismiss
    
    let mode: ContactScanMode
    let onExtracted: (ExtractedContactInfo) -> Void
    
    @State private var showingSourcePicker = true
    @State private var showingCamera = false
    @State private var showingPhotoPicker = false
    @State private var showingFilePicker = false
    @State private var showingSelectionBox = false
    
    @State private var selectedImage: UIImage?
    @State private var isProcessing = false
    @State private var extractedInfo = ExtractedContactInfo()
    @State private var rawText = ""
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationStack {
            Group {
                if showingSourcePicker {
                    sourceSelectionView
                } else if showingSelectionBox, let image = selectedImage {
                    SelectionBoxScannerView(
                        image: image,
                        mode: mode,
                        onExtract: { info, text in
                            extractedInfo = info
                            rawText = text
                            showingSelectionBox = false
                        },
                        onCancel: {
                            showingSelectionBox = false
                            showingSourcePicker = true
                        }
                    )
                } else if isProcessing {
                    processingView
                } else if extractedInfo.isValid || !rawText.isEmpty {
                    reviewView
                } else {
                    sourceSelectionView
                }
            }
            .navigationTitle(mode.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .fullScreenCover(isPresented: $showingCamera) {
                SmartDocumentScanner(capturedImage: Binding(
                    get: { self.selectedImage },
                    set: { newImage in
                        if let image = newImage {
                            self.selectedImage = image
                            self.showingSelectionBox = true
                            self.showingSourcePicker = false
                        }
                    }
                ))
            }
            .sheet(isPresented: $showingPhotoPicker) {
                ContactPhotoPickerView { image in
                    selectedImage = image
                    showingSelectionBox = true
                    showingSourcePicker = false
                }
            }
            .sheet(isPresented: $showingFilePicker) {
                ContactDocumentPickerView { image in
                    selectedImage = image
                    showingSelectionBox = true
                    showingSourcePicker = false
                }
            }
        }
    }
    
    // MARK: - Source Selection View
    
    private var sourceSelectionView: some View {
        VStack(spacing: 24) {
            Image(systemName: mode.icon)
                .font(.system(size: 60))
                .foregroundColor(.accentColor)
                .padding(.top, 40)
            
            Text("Scan \(mode == .provider ? "Provider" : "Patient") Information")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Choose a source to extract contact details automatically")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            VStack(spacing: 16) {
                // Camera
                Button {
                    showingSourcePicker = false
                    showingCamera = true
                } label: {
                    ScanSourceButton(
                        icon: "camera.fill",
                        title: "Take Photo",
                        subtitle: "Capture with camera"
                    )
                }
                
                // Photo Library
                Button {
                    showingSourcePicker = false
                    showingPhotoPicker = true
                } label: {
                    ScanSourceButton(
                        icon: "photo.on.rectangle",
                        title: "Photo Library",
                        subtitle: "Choose existing photo"
                    )
                }
                
                // Files
                Button {
                    showingSourcePicker = false
                    showingFilePicker = true
                } label: {
                    ScanSourceButton(
                        icon: "doc.fill",
                        title: "Import File",
                        subtitle: "PDF or image file"
                    )
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            
            Spacer()
        }
    }
    
    // MARK: - Processing View
    
    private var processingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
            
            Text("Analyzing image...")
                .font(.headline)
            
            Text("Extracting contact information")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Review View
    
    private var reviewView: some View {
        Form {
            if let image = selectedImage {
                Section {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 150)
                        .cornerRadius(8)
                        .frame(maxWidth: .infinity)
                }
            }
            
            Section("Extracted Information") {
                if mode == .provider {
                    TextField("Name/Facility", text: $extractedInfo.name)
                    TextField("Organization", text: $extractedInfo.organization)
                    TextField("Phone", text: $extractedInfo.phone)
                        .keyboardType(.phonePad)
                    TextField("Email", text: $extractedInfo.email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                    TextField("Fax", text: $extractedInfo.fax)
                        .keyboardType(.phonePad)
                    TextField("Website", text: $extractedInfo.website)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                    TextField("NPI", text: $extractedInfo.npi)
                        .keyboardType(.numberPad)
                } else {
                    // Patient mode - Name, Account #, Notes
                    TextField("First Name", text: $extractedInfo.firstName)
                    TextField("Last Name", text: $extractedInfo.lastName)
                    TextField("Account / Member ID", text: $extractedInfo.accountNumber)
                }
            }
            
            if mode == .provider {
                Section("Address") {
                    TextField("Street Address", text: $extractedInfo.address)
                    TextField("City", text: $extractedInfo.city)
                    TextField("State", text: $extractedInfo.state)
                    TextField("ZIP Code", text: $extractedInfo.zipCode)
                        .keyboardType(.numberPad)
                }
            }
            
            if mode == .patient && !extractedInfo.notes.isEmpty {
                Section("Notes / Coverage Info") {
                    TextEditor(text: $extractedInfo.notes)
                        .frame(minHeight: 80)
                }
            }
            
            if !rawText.isEmpty {
                Section("Raw Text") {
                    Text(rawText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(10)
                }
            }
            
            Section {
                Button {
                    onExtracted(extractedInfo)
                    dismiss()
                } label: {
                    HStack {
                        Spacer()
                        Text("Use This Information")
                            .fontWeight(.semibold)
                        Spacer()
                    }
                }
                .disabled(!extractedInfo.isValid && extractedInfo.accountNumber.isEmpty && extractedInfo.notes.isEmpty)
                
                Button {
                    // Reset and scan again
                    selectedImage = nil
                    extractedInfo = ExtractedContactInfo()
                    rawText = ""
                    showingSourcePicker = true
                } label: {
                    HStack {
                        Spacer()
                        Text("Scan Again")
                        Spacer()
                    }
                }
            }
            
            if let error = errorMessage {
                Section {
                    Text(error)
                        .foregroundColor(.yellow)
                        .font(.caption)
                }
            }
        }
    }
    
    // MARK: - Image Processing
    
    private func processImage(_ image: UIImage) {
        isProcessing = true
        errorMessage = nil
        
        Task {
            do {
                let text = try await extractText(from: image)
                rawText = text
                extractedInfo = parseContactInfo(from: text)
                isProcessing = false
                showingSourcePicker = false
            } catch {
                errorMessage = "Failed to extract text: \(error.localizedDescription)"
                isProcessing = false
                showingSourcePicker = true
            }
        }
    }
    
    private func extractText(from image: UIImage) async throws -> String {
        guard let cgImage = image.cgImage else {
            throw NSError(domain: "ContactScanner", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid image"])
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
                
                let text = observations
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")
                
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
    
    // MARK: - Contact Info Parsing
    
    private func parseContactInfo(from text: String) -> ExtractedContactInfo {
        var info = ExtractedContactInfo()
        let lines = text.components(separatedBy: .newlines)
        
        // Patterns
        let phonePattern = #"\(?\d{3}\)?[-.\s]?\d{3}[-.\s]?\d{4}"#
        let emailPattern = #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#
        let zipPattern = #"\b\d{5}(-\d{4})?\b"#
        let statePattern = #"\b(AL|AK|AZ|AR|CA|CO|CT|DE|FL|GA|HI|ID|IL|IN|IA|KS|KY|LA|ME|MD|MA|MI|MN|MS|MO|MT|NE|NV|NH|NJ|NM|NY|NC|ND|OH|OK|OR|PA|RI|SC|SD|TN|TX|UT|VT|VA|WA|WV|WI|WY)\b"#
        let npiPattern = #"\b\d{10}\b"#
        let faxPattern = #"(?i)(?:fax|f)[\s:]*\(?\d{3}\)?[-.\s]?\d{3}[-.\s]?\d{4}"#
        let websitePattern = #"(?i)(?:www\.|https?://)[A-Za-z0-9.-]+\.[A-Za-z]{2,}(?:/[^\s]*)?"#
        let dobPattern = #"(?i)(?:dob|birth|born|d\.o\.b)[\s:]*(\d{1,2}[/-]\d{1,2}[/-]\d{2,4})"#
        
        var foundPhones: [String] = []
        var foundEmails: [String] = []
        
        // ============================================================
        // PASS 1: Tag-based extraction
        // Look for labeled fields like "Patient Name: John Doe"
        // The tag/label is stripped — only the value is kept.
        // ============================================================
        
        // Tags that map to patient name
        let nameTagPatterns = [
            #"(?i)(?:patient\s*name|name)\s*[:]\s*(.+)"#
        ]
        
        // Tags that map to account number
        let accountTagPatterns = [
            #"(?i)(?:account\s*#|account\s*number|account|acct\s*#|acct)\s*[:]\s*(.+)"#
        ]
        
        // Tags that map to insurance
        let insuranceTagPatterns = [
            #"(?i)(?:insurance|ins|carrier|plan|payer)\s*[:]\s*(.+)"#
        ]
        
        // Tags that map to date of service
        let dateTagPatterns = [
            #"(?i)(?:date\s*of\s*service|service\s*date|dos|visit\s*date)\s*[:]\s*(.+)"#,
            #"(?i)(?:date)\s*[:]\s*(.+)"#  // Generic "Date:" — lower priority
        ]
        
        // Tags that map to DOB
        let dobTagPatterns = [
            #"(?i)(?:date\s*of\s*birth|dob|d\.o\.b\.?|birth\s*date)\s*[:]\s*(.+)"#
        ]
        
        // Set of line indices consumed by tag matching (skip in pass 2)
        var tagConsumedLines: Set<Int> = []
        
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            
            // --- Patient Name tags ---
            if info.firstName.isEmpty && info.name.isEmpty {
                for pattern in nameTagPatterns {
                    if let value = extractTagValue(from: trimmed, pattern: pattern) {
                        let nameParts = value.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                        if nameParts.count >= 2 {
                            info.firstName = nameParts[0]
                            info.lastName = nameParts.dropFirst().joined(separator: " ")
                        } else if nameParts.count == 1 {
                            info.lastName = nameParts[0]
                        }
                        if !value.isEmpty { info.name = value }
                        tagConsumedLines.insert(index)
                        break
                    }
                }
            }
            
            // --- Account tags ---
            if info.accountNumber.isEmpty {
                for pattern in accountTagPatterns {
                    if let value = extractTagValue(from: trimmed, pattern: pattern) {
                        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !cleaned.isEmpty && cleaned.count >= 2 {
                            info.accountNumber = cleaned
                            tagConsumedLines.insert(index)
                            break
                        }
                    }
                }
            }
            
            // --- DOB tags (check before generic date) ---
            if info.dateOfBirth.isEmpty {
                for pattern in dobTagPatterns {
                    if let value = extractTagValue(from: trimmed, pattern: pattern) {
                        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !cleaned.isEmpty {
                            info.dateOfBirth = cleaned
                            tagConsumedLines.insert(index)
                            break
                        }
                    }
                }
            }
            
            // --- Insurance tags ---
            if info.insurance.isEmpty {
                for pattern in insuranceTagPatterns {
                    if let value = extractTagValue(from: trimmed, pattern: pattern) {
                        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !cleaned.isEmpty {
                            info.insurance = cleaned
                            tagConsumedLines.insert(index)
                            break
                        }
                    }
                }
            }
            
            // --- Date of Service tags ---
            if info.dateOfService.isEmpty {
                for pattern in dateTagPatterns {
                    if let value = extractTagValue(from: trimmed, pattern: pattern) {
                        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !cleaned.isEmpty {
                            info.dateOfService = cleaned
                            tagConsumedLines.insert(index)
                            break
                        }
                    }
                }
            }
        }
        
        // ============================================================
        // PASS 2: Pattern-based extraction (existing logic)
        // Runs on lines not already consumed by tag matching.
        // ============================================================
        
        for (index, line) in lines.enumerated() {
            // Skip lines already handled by tag extraction
            if tagConsumedLines.contains(index) { continue }
            
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            let lowercased = line.lowercased()
            
            // Email
            if let match = line.range(of: emailPattern, options: .regularExpression) {
                let email = String(line[match])
                foundEmails.append(email)
                if info.email.isEmpty {
                    info.email = email
                }
            }
            
            // Website
            if let match = line.range(of: websitePattern, options: .regularExpression) {
                if info.website.isEmpty {
                    info.website = String(line[match])
                }
            }
            
            // Fax (before general phone to avoid misclassification)
            if let match = line.range(of: faxPattern, options: .regularExpression) {
                let faxLine = String(line[match])
                if let phoneMatch = faxLine.range(of: phonePattern, options: .regularExpression) {
                    info.fax = String(faxLine[phoneMatch])
                }
            }
            
            // Phone
            if let match = line.range(of: phonePattern, options: .regularExpression) {
                let phone = String(line[match])
                // Skip if this is a fax number
                if !lowercased.contains("fax") {
                    foundPhones.append(phone)
                    if info.phone.isEmpty {
                        info.phone = phone
                    }
                }
            }
            
            // NPI (10-digit number, common for providers)
            if mode == .provider {
                if lowercased.contains("npi") {
                    if let match = line.range(of: npiPattern, options: .regularExpression) {
                        info.npi = String(line[match])
                    }
                }
            }
            
            // DOB (for patients, only if not already found by tags)
            if mode == .patient && info.dateOfBirth.isEmpty {
                if let match = line.range(of: dobPattern, options: .regularExpression) {
                    let dobLine = String(line[match])
                    if let dateMatch = dobLine.range(of: #"\d{1,2}[/-]\d{1,2}[/-]\d{2,4}"#, options: .regularExpression) {
                        info.dateOfBirth = String(dobLine[dateMatch])
                    }
                }
            }
            
            // State
            if let match = line.range(of: statePattern, options: .regularExpression) {
                if info.state.isEmpty {
                    info.state = String(line[match])
                }
            }
            
            // ZIP
            if let match = line.range(of: zipPattern, options: .regularExpression) {
                if info.zipCode.isEmpty {
                    info.zipCode = String(line[match])
                }
            }
            
            // City (usually before state on same line or previous line)
            if !info.state.isEmpty && info.city.isEmpty {
                // Look for "City, ST" or "City ST" pattern
                let cityStatePattern = #"([A-Za-z\s]+),?\s*"# + info.state
                if let match = line.range(of: cityStatePattern, options: .regularExpression) {
                    let cityState = String(line[match])
                    info.city = cityState.replacingOccurrences(of: info.state, with: "")
                        .replacingOccurrences(of: ",", with: "")
                        .trimmingCharacters(in: .whitespaces)
                }
            }
            
            // Street address - look for common indicators
            if info.address.isEmpty {
                if lowercased.contains("street") || lowercased.contains(" st") ||
                   lowercased.contains("avenue") || lowercased.contains(" ave") ||
                   lowercased.contains("road") || lowercased.contains(" rd") ||
                   lowercased.contains("boulevard") || lowercased.contains(" blvd") ||
                   lowercased.contains("drive") || lowercased.contains(" dr") ||
                   lowercased.contains("lane") || lowercased.contains(" ln") ||
                   lowercased.contains("court") || lowercased.contains(" ct") ||
                   lowercased.contains("circle") || lowercased.contains(" cir") ||
                   lowercased.contains("way") || lowercased.contains("place") ||
                   line.range(of: #"^\d+\s+[A-Za-z]"#, options: .regularExpression) != nil {
                    info.address = trimmedLine
                }
            }
            
            // Account / Member ID (only if not already found by tags)
            if mode == .patient && info.accountNumber.isEmpty {
                let accountPatterns = [
                    #"(?i)(?:account|acct|acc)[\s#:.]*([A-Za-z0-9\-]{3,25})"#,
                    #"(?i)(?:member|subscriber|mbr)[\s#:.]*(?:id[\s#:.]*)?([A-Za-z0-9\-]{3,25})"#,
                    #"(?i)(?:patient|pt)[\s#:.]*(?:id[\s#:.]*)?([A-Za-z0-9\-]{3,25})"#,
                    #"(?i)(?:policy|group)[\s#:.]*(?:id[\s#:.]*)?([A-Za-z0-9\-]{3,25})"#,
                    #"(?i)(?:id)[\s#:.]+([A-Za-z0-9\-]{3,25})"#
                ]
                
                for pattern in accountPatterns {
                    if let regex = try? NSRegularExpression(pattern: pattern, options: []),
                       let match = regex.firstMatch(in: trimmedLine, options: [], range: NSRange(trimmedLine.startIndex..., in: trimmedLine)) {
                        if match.numberOfRanges > 1,
                           let range = Range(match.range(at: 1), in: trimmedLine) {
                            let accountNum = String(trimmedLine[range]).trimmingCharacters(in: .whitespaces)
                            if !accountNum.isEmpty && accountNum.count >= 3 {
                                info.accountNumber = accountNum
                            }
                        }
                    }
                }
            }
            
            // Name detection (only if not already found by tags)
            if index < 5 && info.name.isEmpty && info.firstName.isEmpty && info.organization.isEmpty {
                // Skip lines that are clearly not names
                let isNotName = lowercased.contains("@") ||
                               lowercased.contains("www") ||
                               lowercased.contains("http") ||
                               lowercased.contains("phone") ||
                               lowercased.contains("fax") ||
                               lowercased.contains("email") ||
                               lowercased.contains("account") ||
                               lowercased.contains("insurance") ||
                               lowercased.contains("date") ||
                               line.range(of: phonePattern, options: .regularExpression) != nil ||
                               trimmedLine.isEmpty
                
                if !isNotName {
                    // Check if it looks like organization (has Inc, LLC, Medical, Clinic, etc.)
                    let orgIndicators = ["inc", "llc", "ltd", "corp", "medical", "clinic", "hospital",
                                        "center", "healthcare", "health", "group", "associates",
                                        "practice", "specialists", "physicians", "pharmacy"]
                    
                    let isOrganization = orgIndicators.contains { lowercased.contains($0) }
                    
                    if isOrganization {
                        info.organization = trimmedLine
                        if mode == .provider {
                            info.name = trimmedLine
                        }
                    } else if mode == .patient {
                        // Try to split into first/last name
                        let nameParts = trimmedLine.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                        if nameParts.count >= 2 {
                            info.firstName = nameParts[0]
                            info.lastName = nameParts.dropFirst().joined(separator: " ")
                        } else if nameParts.count == 1 {
                            info.lastName = nameParts[0]
                        }
                    } else {
                        info.name = trimmedLine
                    }
                }
            }
        }
        
        return info
    }
    
    /// Extracts the value after a tagged label using a regex with a capture group.
    /// Returns nil if the pattern doesn't match or the captured value is empty.
    private func extractTagValue(from text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let nsRange = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: nsRange) else { return nil }
        guard match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else { return nil }
        let value = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

// MARK: - Scan Source Button

struct ScanSourceButton: View {
    let icon: String
    let title: String
    let subtitle: String
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.accentColor)
                .frame(width: 44, height: 44)
                .background(Color.accentColor.opacity(0.1))
                .cornerRadius(10)
            
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
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
}

// MARK: - Selection Box Scanner View

// MARK: - Selection Box Scanner View (matches Scan Bill look & feel)

struct SelectionBoxScannerView: View {
    let image: UIImage
    let mode: ContactScanMode
    let onExtract: (ExtractedContactInfo, String) -> Void
    let onCancel: () -> Void
    
    // Single selection box — uses same SelectionBox type as bill scanner
    @State private var infoBox = SelectionBox(
        position: CGPoint(x: 0.5, y: 0.35),
        size: CGSize(width: 0.9, height: 0.55)
    )
    
    // Zoom and pan state
    @State private var zoomScale: CGFloat = 1.0
    @State private var lastZoomScale: CGFloat = 1.0
    @State private var panOffset: CGSize = .zero
    @State private var lastPanOffset: CGSize = .zero
    @State private var isProcessing = false
    
    private var boxColor: Color {
        mode == .provider ? .green : .blue
    }
    
    private var boxLabel: String {
        mode == .provider ? "Provider Info" : "Patient Info"
    }
    
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Instructions bar (matches bill scanner)
                instructionsBar
                
                // Image with selection box — zoomable
                ZStack {
                    GeometryReader { imageGeometry in
                        let imageFrame = calculateImageFrame(in: imageGeometry.size)
                        
                        ZStack {
                            // Zoomable/pannable image
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: imageFrame.size.width, height: imageFrame.size.height)
                                .position(x: imageGeometry.size.width / 2, y: imageGeometry.size.height / 2)
                            
                            // Single selection box overlay — uses DraggableBox from bill scanner
                            DraggableBox(
                                box: $infoBox,
                                containerSize: imageFrame.size,
                                offset: imageFrame.origin,
                                color: boxColor,
                                label: boxLabel,
                                isActive: true,
                                zoomScale: zoomScale
                            )
                        }
                        .coordinateSpace(name: "billImageArea")
                        .scaleEffect(zoomScale)
                        .offset(panOffset)
                        .gesture(
                            SimultaneousGesture(
                                MagnificationGesture()
                                    .onChanged { value in
                                        let newScale = lastZoomScale * value
                                        zoomScale = min(max(newScale, 1.0), 5.0)
                                    }
                                    .onEnded { _ in
                                        lastZoomScale = zoomScale
                                        if zoomScale <= 1.0 {
                                            withAnimation(.easeOut(duration: 0.2)) {
                                                panOffset = .zero
                                                lastPanOffset = .zero
                                            }
                                        }
                                    },
                                DragGesture()
                                    .onChanged { value in
                                        if zoomScale > 1.0 {
                                            panOffset = CGSize(
                                                width: lastPanOffset.width + value.translation.width,
                                                height: lastPanOffset.height + value.translation.height
                                            )
                                        }
                                    }
                                    .onEnded { _ in
                                        lastPanOffset = panOffset
                                    }
                            )
                        )
                        .gesture(
                            TapGesture(count: 2)
                                .onEnded {
                                    withAnimation(.easeOut(duration: 0.3)) {
                                        if zoomScale > 1.0 {
                                            zoomScale = 1.0
                                            lastZoomScale = 1.0
                                            panOffset = .zero
                                            lastPanOffset = .zero
                                        } else {
                                            zoomScale = 2.5
                                            lastZoomScale = 2.5
                                        }
                                    }
                                }
                        )
                    }
                    
                    // Processing overlay
                    if isProcessing {
                        Color.black.opacity(0.4)
                            .ignoresSafeArea()
                        VStack(spacing: 12) {
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(1.5)
                            Text("Extracting...")
                                .font(.subheadline)
                                .foregroundColor(.white)
                        }
                        .padding(30)
                        .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))
                    }
                }
                .clipped()
                
                // Bottom controls (matches bill scanner)
                bottomControls
            }
        }
    }
    
    // MARK: - Instructions Bar
    
    private var instructionsBar: some View {
        VStack(spacing: 4) {
            Text("Position box over \(mode == .provider ? "provider" : "patient") information")
                .font(.subheadline)
                .fontWeight(.medium)
            Text("Pinch to zoom \u{2022} Drag box \u{2022} Pinch corners to resize")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(Color("BrandDeepNavy"))
    }
    
    // MARK: - Bottom Controls
    
    private var bottomControls: some View {
        VStack(spacing: 12) {
            // Legend
            HStack(spacing: 16) {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(boxColor.opacity(0.3))
                        .overlay(RoundedRectangle(cornerRadius: 3).stroke(boxColor, lineWidth: 2))
                        .frame(width: 16, height: 16)
                    Text(boxLabel)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.top, 10)
            
            // Extract button
            Button {
                extractFromRegion()
            } label: {
                HStack {
                    if isProcessing {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "text.viewfinder")
                    }
                    Text(isProcessing ? "Processing..." : "Extract Text")
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(isProcessing ? Color.gray : Color.accentColor)
                .cornerRadius(12)
            }
            .disabled(isProcessing)
            .padding(.horizontal)
            .padding(.bottom, 10)
        }
        .background(Color("BrandDeepNavy"))
    }
    
    // MARK: - Image Frame Calculation
    
    private func calculateImageFrame(in containerSize: CGSize) -> CGRect {
        let imageAspect = image.size.width / image.size.height
        let containerAspect = containerSize.width / containerSize.height
        
        var size: CGSize
        var origin: CGPoint
        
        if imageAspect > containerAspect {
            size = CGSize(width: containerSize.width, height: containerSize.width / imageAspect)
            origin = CGPoint(x: 0, y: (containerSize.height - size.height) / 2)
        } else {
            size = CGSize(width: containerSize.height * imageAspect, height: containerSize.height)
            origin = CGPoint(x: (containerSize.width - size.width) / 2, y: 0)
        }
        
        return CGRect(origin: origin, size: size)
    }
    
    // MARK: - Extract from Region
    
    private func extractFromRegion() {
        isProcessing = true
        
        Task {
            var info = ExtractedContactInfo()
            var allText = ""
            
            // OCR on the selected region
            let rect = normalizedToImageRect(infoBox, imageSize: image.size)
            if let croppedImage = cropImage(image, to: rect) {
                let text = await extractText(from: croppedImage)
                allText = text
                
                if mode == .provider {
                    parseProviderFromText(text, into: &info)
                    parseAddressFromText(text, into: &info)
                    parseContactFromText(text, into: &info)
                } else {
                    parsePatientNameFromText(text, into: &info)
                    parseAccountFromText(text, into: &info)
                    parseOtherFromText(text, into: &info)
                    parseContactFromText(text, into: &info)
                    parseAddressFromText(text, into: &info)
                    parseTaggedFieldsFromText(text, into: &info)
                }
            }
            
            // Fallback: full image OCR if region gave nothing
            if info.firstName.isEmpty && info.name.isEmpty && info.organization.isEmpty {
                let fullText = await extractText(from: image)
                if !fullText.isEmpty {
                    if mode == .provider {
                        parseProviderFromText(fullText, into: &info)
                        parseAddressFromText(fullText, into: &info)
                        parseContactFromText(fullText, into: &info)
                    } else {
                        parsePatientNameFromText(fullText, into: &info)
                        parseAccountFromText(fullText, into: &info)
                    }
                    allText += "\n(fallback: full image)"
                }
            }
            
            await MainActor.run {
                isProcessing = false
                onExtract(info, allText)
            }
        }
    }
    
    // MARK: - Coordinate Conversion
    
    private func normalizedToImageRect(_ box: SelectionBox, imageSize: CGSize) -> CGRect {
        let x = (box.position.x - box.size.width / 2) * imageSize.width
        let y = (box.position.y - box.size.height / 2) * imageSize.height
        let w = box.size.width * imageSize.width
        let h = box.size.height * imageSize.height
        return CGRect(x: max(0, x), y: max(0, y),
                      width: min(w, imageSize.width - max(0, x)),
                      height: min(h, imageSize.height - max(0, y)))
    }
    
    private func cropImage(_ image: UIImage, to rect: CGRect) -> UIImage? {
        // Normalize orientation first
        let normalizedImage: UIImage
        if image.imageOrientation != .up {
            UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
            image.draw(in: CGRect(origin: .zero, size: image.size))
            normalizedImage = UIGraphicsGetImageFromCurrentImageContext() ?? image
            UIGraphicsEndImageContext()
        } else {
            normalizedImage = image
        }
        
        guard let cgImage = normalizedImage.cgImage else { return nil }
        let clampedRect = rect.intersection(CGRect(origin: .zero, size: normalizedImage.size))
        guard !clampedRect.isEmpty, let cropped = cgImage.cropping(to: clampedRect) else { return nil }
        return UIImage(cgImage: cropped)
    }
    
    // MARK: - OCR
    
    private func extractText(from image: UIImage) async -> String {
        guard let cgImage = image.cgImage else { return "" }
        
        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: "")
                    return
                }
                
                let text = observations
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")
                
                continuation.resume(returning: text)
            }
            
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: "")
            }
        }
    }
    
    // MARK: - Provider Parsing
    
    private func parseProviderFromText(_ text: String, into info: inout ExtractedContactInfo) {
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        
        for line in lines {
            let lower = line.lowercased()
            // Look for labeled fields
            if lower.hasPrefix("provider:") || lower.hasPrefix("facility:") || lower.hasPrefix("clinic:") || lower.hasPrefix("hospital:") {
                let val = String(line[line.index(after: line.firstIndex(of: ":")!)...]).trimmingCharacters(in: .whitespaces)
                if info.organization.isEmpty { info.organization = val }
                continue
            }
            if lower.hasPrefix("npi:") || lower.hasPrefix("npi #:") {
                let val = String(line[line.index(after: line.firstIndex(of: ":")!)...]).trimmingCharacters(in: .whitespaces)
                if info.npi.isEmpty { info.npi = val }
                continue
            }
        }
        
        // Fallback: first non-label line is usually the facility name
        if info.organization.isEmpty && info.name.isEmpty {
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.contains(":") { continue }
                let upper = trimmed.uppercased()
                if upper.contains("@") || upper.contains("WWW.") { continue }
                if trimmed.first?.isNumber == true { continue } // address
                if trimmed.filter({ $0.isNumber }).count > trimmed.count / 2 { continue } // mostly digits
                info.organization = trimmed
                break
            }
        }
    }
    
    // MARK: - Patient Name Parsing
    
    private func parsePatientNameFromText(_ text: String, into info: inout ExtractedContactInfo) {
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        
        for line in lines {
            let lower = line.lowercased()
            
            // Skip non-name lines
            if lower.contains("@") || lower.contains("www.") || lower.contains("http") { continue }
            if line.range(of: #"\(?\d{3}\)?[-. ]?\d{3}[-. ]?\d{4}"#, options: .regularExpression) != nil { continue }
            if line.hasSuffix(":") && !line.contains(" ") { continue }
            if line.range(of: #"^\d+$"#, options: .regularExpression) != nil { continue }
            let digitCount = line.filter { $0.isNumber }.count
            if digitCount > line.count / 2 && digitCount > 4 { continue }
            // Skip barcode/postal artifacts
            if line.hasPrefix(">") || line.uppercased().contains("ADDRESS SERVICE") { continue }
            if line.uppercased().contains("ADDRESSEE") { continue }
            
            let skipLabels = ["division", "account", "member", "policy", "group", "plan",
                             "date", "period", "balance", "total", "amount", "payment",
                             "statement", "invoice", "bill", "page", "customer", "voucher"]
            if skipLabels.contains(where: { lower.hasPrefix($0) }) { continue }
            
            // Look for labeled name
            if lower.hasPrefix("patient:") || lower.hasPrefix("name:") || lower.hasPrefix("patient name:") {
                if let idx = line.firstIndex(of: ":") {
                    let nameStr = String(line[line.index(after: idx)...]).trimmingCharacters(in: .whitespaces)
                    if nameStr.count >= 2 { parseNameParts(nameStr, into: &info); return }
                }
                continue
            }
            
            // Unlabeled name: 2-4 words, all letters
            let words = line.split(separator: " ")
            if words.count >= 2 && words.count <= 5 && words.allSatisfy({ $0.first?.isLetter == true }) {
                if line.rangeOfCharacter(from: .decimalDigits) == nil {
                    parseNameParts(line, into: &info)
                    return
                }
            }
        }
    }
    
    private func parseNameParts(_ nameStr: String, into info: inout ExtractedContactInfo) {
        let parts = nameStr.trimmingCharacters(in: .whitespaces).split(separator: " ").map(String.init)
        guard !parts.isEmpty else { return }
        
        info.name = nameStr
        info.firstName = parts[0]
        if parts.count == 2 {
            info.lastName = parts[1]
        } else if parts.count >= 3 {
            // Handle "LAST, FIRST MIDDLE" or "FIRST MIDDLE LAST"
            if parts[0].hasSuffix(",") {
                info.lastName = parts[0].replacingOccurrences(of: ",", with: "")
                info.firstName = parts[1]
            } else {
                info.lastName = parts.last!
                info.firstName = parts[0]
            }
        }
    }
    
    // MARK: - Address Parsing
    
    private func parseAddressFromText(_ text: String, into info: inout ExtractedContactInfo) {
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        
        for (i, line) in lines.enumerated() {
            let upper = line.uppercased()
            let streetIndicators = ["STREET", "ST.", "ST ", "AVE", "AVENUE", "BLVD", "DRIVE", "DR.",
                                    "ROAD", "RD.", "LANE", "LN.", "WAY", "SUITE", "STE",
                                    "P.O. BOX", "PO BOX", "COURT", "CT.", "CIRCLE", "CIR",
                                    "PLACE", "PL.", "PIKE", "HWY", "HIGHWAY",
                                    "NORTH ", "SOUTH ", "EAST ", "WEST "]
            
            let isAddress = streetIndicators.contains(where: { upper.contains($0) })
                || (line.first?.isNumber == true && line.count > 10)
            
            if isAddress && info.address.isEmpty {
                info.address = line
                // Check next line for city/state/ZIP
                if i + 1 < lines.count {
                    let next = lines[i + 1]
                    if next.range(of: #"\b\d{5}(-\d{4})?\b"#, options: .regularExpression) != nil {
                        // Parse city, state, ZIP
                        let parts = next.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                        if parts.count >= 2 {
                            info.city = parts[0]
                            let stateZip = parts[1].trimmingCharacters(in: .whitespaces)
                            let szParts = stateZip.split(separator: " ").map(String.init)
                            if let st = szParts.first { info.state = st }
                            if let zip = szParts.last, zip.rangeOfCharacter(from: .decimalDigits) != nil { info.zipCode = zip }
                        }
                    }
                }
                break
            }
            
            // Also check for ZIP code line (city, state ZIP)
            if line.range(of: #"\b\d{5}(-\d{4})?\b"#, options: .regularExpression) != nil && info.city.isEmpty {
                let parts = line.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                if parts.count >= 2 {
                    info.city = parts[0]
                    let stateZip = parts[1].trimmingCharacters(in: .whitespaces)
                    let szParts = stateZip.split(separator: " ").map(String.init)
                    if let st = szParts.first { info.state = st }
                    if let zip = szParts.last, zip.rangeOfCharacter(from: .decimalDigits) != nil { info.zipCode = zip }
                }
            }
        }
    }
    
    // MARK: - Contact Parsing (Phone, Email, Fax, Website)
    
    private func parseContactFromText(_ text: String, into info: inout ExtractedContactInfo) {
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        
        let phonePattern = #"\(?\d{3}\)?[-. ]?\d{3}[-. ]?\d{4}"#
        let emailPattern = #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#
        let webPattern = #"(?:https?://|www\.)[A-Za-z0-9._~:/?#@!$&'()*+,;=-]+"#
        
        for line in lines {
            let lower = line.lowercased()
            
            // Fax
            if lower.contains("fax") && info.fax.isEmpty {
                if let range = line.range(of: phonePattern, options: .regularExpression) {
                    info.fax = String(line[range])
                }
                continue
            }
            
            // Phone (not fax)
            if info.phone.isEmpty {
                if let range = line.range(of: phonePattern, options: .regularExpression) {
                    info.phone = String(line[range])
                    continue
                }
            }
            
            // Email
            if info.email.isEmpty {
                if let range = line.range(of: emailPattern, options: .regularExpression) {
                    info.email = String(line[range])
                    continue
                }
            }
            
            // Website
            if info.website.isEmpty {
                if let range = line.range(of: webPattern, options: .regularExpression) {
                    info.website = String(line[range])
                    continue
                }
            }
        }
    }
    
    // MARK: - Account Parsing
    
    private func parseAccountFromText(_ text: String, into info: inout ExtractedContactInfo) {
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        
        for line in lines {
            let lower = line.lowercased()
            if lower.hasPrefix("account") || lower.hasPrefix("acct") || lower.hasPrefix("member id") || lower.hasPrefix("id #") || lower.hasPrefix("mrn") {
                if let idx = line.firstIndex(of: ":") {
                    let val = String(line[line.index(after: idx)...]).trimmingCharacters(in: .whitespaces)
                    if !val.isEmpty && info.accountNumber.isEmpty { info.accountNumber = val }
                }
            }
        }
    }
    
    // MARK: - Other Fields (DOB, Insurance, DOS)
    
    private func parseOtherFromText(_ text: String, into info: inout ExtractedContactInfo) {
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        
        for line in lines {
            let lower = line.lowercased()
            if (lower.contains("birth") || lower == "dob" || lower.hasPrefix("dob:") || lower.hasPrefix("dob ")) && info.dateOfBirth.isEmpty {
                if let idx = line.firstIndex(of: ":") {
                    info.dateOfBirth = String(line[line.index(after: idx)...]).trimmingCharacters(in: .whitespaces)
                }
            }
            if (lower.contains("insurance") || lower.contains("carrier") || lower.contains("payer")) && info.insurance.isEmpty {
                if let idx = line.firstIndex(of: ":") {
                    info.insurance = String(line[line.index(after: idx)...]).trimmingCharacters(in: .whitespaces)
                }
            }
        }
    }
    
    // MARK: - Tagged Fields
    
    private func parseTaggedFieldsFromText(_ text: String, into info: inout ExtractedContactInfo) {
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        
        for line in lines {
            let lower = line.lowercased()
            guard let colonIdx = line.firstIndex(of: ":") else { continue }
            let val = String(line[line.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)
            guard !val.isEmpty else { continue }
            
            if lower.hasPrefix("dob") || lower.hasPrefix("date of birth") {
                if info.dateOfBirth.isEmpty { info.dateOfBirth = val }
            } else if lower.hasPrefix("insurance") || lower.hasPrefix("carrier") || lower.hasPrefix("plan") {
                if info.insurance.isEmpty { info.insurance = val }
            } else if lower.hasPrefix("date of service") || lower.hasPrefix("dos") || lower.hasPrefix("service date") {
                if info.dateOfService.isEmpty { info.dateOfService = val }
            } else if lower.hasPrefix("member") || lower.hasPrefix("subscriber") || lower.hasPrefix("policy") {
                if info.accountNumber.isEmpty { info.accountNumber = val }
            }
        }
    }
}

struct ContactCameraView: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ContactCameraView
        
        init(_ parent: ContactCameraView) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onCapture(image)
            }
            parent.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

// MARK: - Photo Picker View

struct ContactPhotoPickerView: UIViewControllerRepresentable {
    let onSelect: (UIImage) -> Void
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
        let parent: ContactPhotoPickerView
        
        init(_ parent: ContactPhotoPickerView) {
            self.parent = parent
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.dismiss()
            
            guard let result = results.first else { return }
            
            result.itemProvider.loadObject(ofClass: UIImage.self) { [weak self] object, error in
                if let image = object as? UIImage {
                    DispatchQueue.main.async {
                        self?.parent.onSelect(image)
                    }
                }
            }
        }
    }
}

// MARK: - Document Picker View

struct ContactDocumentPickerView: UIViewControllerRepresentable {
    let onSelect: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let types: [UTType] = [.image, .pdf]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types)
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: ContactDocumentPickerView
        
        init(_ parent: ContactDocumentPickerView) {
            self.parent = parent
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            
            _ = url.startAccessingSecurityScopedResource()
            defer { url.stopAccessingSecurityScopedResource() }
            
            if url.pathExtension.lowercased() == "pdf" {
                if let image = renderPDFToImage(url: url) {
                    parent.onSelect(image)
                }
            } else if let data = try? Data(contentsOf: url),
                      let image = UIImage(data: data) {
                parent.onSelect(image)
            }
        }
        
        private func renderPDFToImage(url: URL) -> UIImage? {
            guard let document = CGPDFDocument(url as CFURL),
                  let page = document.page(at: 1) else {
                return nil
            }
            
            let pageRect = page.getBoxRect(.mediaBox)
            let scale: CGFloat = 2.0
            let size = CGSize(width: pageRect.width * scale, height: pageRect.height * scale)
            
            let renderer = UIGraphicsImageRenderer(size: size)
            return renderer.image { ctx in
                UIColor.white.setFill()
                ctx.fill(CGRect(origin: .zero, size: size))
                
                ctx.cgContext.translateBy(x: 0, y: size.height)
                ctx.cgContext.scaleBy(x: scale, y: -scale)
                ctx.cgContext.drawPDFPage(page)
            }
        }
    }
}

// MARK: - Scan Button for Forms

struct ScanContactButton: View {
    let mode: ContactScanMode
    let onScan: (ExtractedContactInfo) -> Void
    
    @State private var showingScanner = false
    
    var body: some View {
        Button {
            showingScanner = true
        } label: {
            Label("Scan Info", systemImage: "doc.text.viewfinder")
        }
        .sheet(isPresented: $showingScanner) {
            ContactInfoScannerView(mode: mode) { info in
                onScan(info)
            }
        }
    }
}
