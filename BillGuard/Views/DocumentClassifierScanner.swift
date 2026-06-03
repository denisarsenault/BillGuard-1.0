//
//  DocumentClassifierScanner.swift
//  BillGuard
//
//  Document scanner that classifies scanned documents and detects "This is not a Bill"
//

import SwiftUI
import VisionKit
import Vision
import PhotosUI

// MARK: - Document Classification Result

struct DocumentClassificationResult {
    var documentType: ScannedDocumentType
    var isNotABill: Bool
    var detectedText: String
    var suggestedName: String
    var confidence: Double
    
    // Detected fields
    var providerName: String?
    var patientName: String?
    var serviceDate: String?
    var totalAmount: String?
    var accountNumber: String?
}

// MARK: - Document Classifier Scanner View

struct DocumentClassifierScannerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var patientDataService: PatientDataService
    @EnvironmentObject var appState: AppState
    
    @State private var showingSourcePicker = true
    @State private var showingCamera = false
    @State private var showingPhotoPicker = false
    @State private var showingFilePicker = false
    
    @State private var selectedImage: UIImage?
    @State private var isProcessing = false
    @State private var classificationResult: DocumentClassificationResult?
    @State private var showingClassificationPrompt = false
    @State private var showingDocumentForm = false
    
    // Document form fields
    @State private var documentName = ""
    @State private var documentType: ScannedDocumentType = .other
    @State private var documentNotes = ""
    @State private var saveAsBill = false
    
    var body: some View {
        NavigationStack {
            Group {
                if showingSourcePicker {
                    sourceSelectionView
                } else if isProcessing {
                    processingView
                } else if showingClassificationPrompt, let result = classificationResult {
                    classificationPromptView(result: result)
                } else if showingDocumentForm {
                    documentFormView
                } else {
                    sourceSelectionView
                }
            }
            .navigationTitle("Scan Document")
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
                            self.processDocument(image)
                        }
                    }
                ))
            }
            .sheet(isPresented: $showingPhotoPicker) {
                DocumentPhotoPickerView { image in
                    selectedImage = image
                    processDocument(image)
                }
            }
            .sheet(isPresented: $showingFilePicker) {
                DocumentFilePickerView { image in
                    selectedImage = image
                    processDocument(image)
                }
            }
        }
    }
    
    // MARK: - Source Selection View
    
    private var sourceSelectionView: some View {
        VStack(spacing: 24) {
            Image(systemName: "doc.text.viewfinder")
                .font(.system(size: 60))
                .foregroundColor(.accentColor)
                .padding(.top, 40)
            
            Text("Scan Document")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Scan any medical document to classify and save it")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            VStack(spacing: 16) {
                Button {
                    showingSourcePicker = false
                    showingCamera = true
                } label: {
                    DocumentSourceButton(
                        icon: "camera.fill",
                        title: "Take Photo",
                        subtitle: "Capture with camera"
                    )
                }
                
                Button {
                    showingSourcePicker = false
                    showingPhotoPicker = true
                } label: {
                    DocumentSourceButton(
                        icon: "photo.on.rectangle",
                        title: "Photo Library",
                        subtitle: "Choose existing photo"
                    )
                }
                
                Button {
                    showingSourcePicker = false
                    showingFilePicker = true
                } label: {
                    DocumentSourceButton(
                        icon: "folder.fill",
                        title: "Import File",
                        subtitle: "PDF or image file"
                    )
                }
            }
            .padding(.horizontal)
            
            Spacer()
        }
    }
    
    // MARK: - Processing View
    
    private var processingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
            
            Text("Analyzing Document...")
                .font(.headline)
            
            Text("Detecting document type and extracting text")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Classification Prompt View
    
    private func classificationPromptView(result: DocumentClassificationResult) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                // Preview image
                if let image = selectedImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 200)
                        .cornerRadius(12)
                        .shadow(radius: 4)
                }
                
                // "This is not a Bill" detection
                if result.isNotABill {
                    VStack(spacing: 12) {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("\"This is not a Bill\" Detected")
                                .font(.headline)
                                .foregroundColor(.orange)
                        }
                        
                        Text("This document appears to be an informational statement, not a bill requiring payment.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        
                        // Option to save as bill anyway
                        Toggle("Save as Bill anyway", isOn: $saveAsBill)
                            .padding()
                            .background(Color(.secondarySystemGroupedBackground))
                            .cornerRadius(10)
                    }
                    .padding()
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(12)
                }
                
                // Detected type
                VStack(alignment: .leading, spacing: 12) {
                    Text("Detected Document Type")
                        .font(.headline)
                    
                    HStack {
                        Image(systemName: result.documentType.icon)
                            .foregroundColor(.accentColor)
                        Text(result.documentType.rawValue)
                            .font(.body)
                        Spacer()
                        Text("\(Int(result.confidence * 100))% confidence")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color(.secondarySystemGroupedBackground))
                    .cornerRadius(10)
                }
                .padding(.horizontal)
                
                // Extracted info
                if result.providerName != nil || result.serviceDate != nil || result.totalAmount != nil {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Extracted Information")
                            .font(.headline)
                        
                        VStack(spacing: 8) {
                            if let provider = result.providerName {
                                extractedInfoRow(label: "Provider", value: provider)
                            }
                            if let patient = result.patientName {
                                extractedInfoRow(label: "Patient", value: patient)
                            }
                            if let date = result.serviceDate {
                                extractedInfoRow(label: "Service Date", value: date)
                            }
                            if let amount = result.totalAmount {
                                extractedInfoRow(label: "Amount", value: amount)
                            }
                            if let account = result.accountNumber {
                                extractedInfoRow(label: "Account #", value: account)
                            }
                        }
                        .padding()
                        .background(Color(.secondarySystemGroupedBackground))
                        .cornerRadius(10)
                    }
                    .padding(.horizontal)
                }
                
                // Action buttons
                VStack(spacing: 12) {
                    if result.isNotABill && !saveAsBill {
                        Button {
                            documentType = .eob  // Default to EOB for "not a bill" docs
                            documentName = result.suggestedName
                            showingClassificationPrompt = false
                            showingDocumentForm = true
                        } label: {
                            HStack {
                                Image(systemName: "doc.fill")
                                Text("Save as Other Documentation")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                    } else {
                        Button {
                            // Navigate to bill scanner with this image
                            // For now, save as bill type document
                            documentType = .bill
                            documentName = result.suggestedName
                            showingClassificationPrompt = false
                            showingDocumentForm = true
                        } label: {
                            HStack {
                                Image(systemName: "doc.text.fill")
                                Text("Save as Bill")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                    }
                    
                    Button {
                        // Change document type
                        documentName = result.suggestedName
                        showingClassificationPrompt = false
                        showingDocumentForm = true
                    } label: {
                        HStack {
                            Image(systemName: "square.and.pencil")
                            Text("Choose Different Type")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.secondarySystemGroupedBackground))
                        .foregroundColor(.primary)
                        .cornerRadius(10)
                    }
                    
                    Button {
                        // Rescan
                        selectedImage = nil
                        classificationResult = nil
                        showingClassificationPrompt = false
                        showingSourcePicker = true
                    } label: {
                        Text("Scan Again")
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
            }
            .padding(.vertical)
        }
    }
    
    private func extractedInfoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .font(.body)
            Spacer()
        }
    }
    
    // MARK: - Document Form View
    
    private var documentFormView: some View {
        Form {
            if let image = selectedImage {
                Section {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 150)
                        .frame(maxWidth: .infinity)
                        .cornerRadius(8)
                }
            }
            
            Section("Document Information") {
                TextField("Document Name", text: $documentName)
                
                Picker("Document Type", selection: $documentType) {
                    ForEach(ScannedDocumentType.allCases, id: \.self) { type in
                        Label(type.rawValue, systemImage: type.icon)
                            .tag(type)
                    }
                }
                
                TextField("Notes (Optional)", text: $documentNotes, axis: .vertical)
                    .lineLimit(3...6)
            }
            
            if let patientId = appState.selectedPatientId,
               let patient = patientDataService.patients.first(where: { $0.id == patientId }) {
                Section("Link To") {
                    HStack {
                        Image(systemName: "person.fill")
                        Text(patient.fullName)
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    }
                }
            }
            
            Section {
                Button {
                    saveDocument()
                } label: {
                    HStack {
                        Spacer()
                        Text("Save Document")
                            .fontWeight(.semibold)
                        Spacer()
                    }
                }
                .disabled(documentName.isEmpty)
            }
        }
        .navigationTitle("Save Document")
    }
    
    // MARK: - Document Processing
    
    private func processDocument(_ image: UIImage) {
        isProcessing = true
        showingSourcePicker = false
        
        Task {
            let text = await extractText(from: image)
            let result = classifyDocument(text: text, image: image)
            
            await MainActor.run {
                classificationResult = result
                isProcessing = false
                showingClassificationPrompt = true
            }
        }
    }
    
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
    
    private func classifyDocument(text: String, image: UIImage) -> DocumentClassificationResult {
        let lowercasedText = text.lowercased()
        
        // Check for "This is not a Bill" variations
        let notABillPhrases = [
            "this is not a bill",
            "not a bill",
            "this is not your bill",
            "do not pay",
            "for your records",
            "for informational purposes",
            "explanation of benefits",
            "this statement is for your information"
        ]
        
        let isNotABill = notABillPhrases.contains { lowercasedText.contains($0) }
        
        // Detect document type
        var detectedType: ScannedDocumentType = .other
        var confidence: Double = 0.5
        
        // EOB detection
        if lowercasedText.contains("explanation of benefits") ||
           lowercasedText.contains("eob") ||
           (lowercasedText.contains("claim") && lowercasedText.contains("paid")) {
            detectedType = .eob
            confidence = 0.9
        }
        // Bill detection
        else if (lowercasedText.contains("amount due") ||
                 lowercasedText.contains("total due") ||
                 lowercasedText.contains("pay this amount") ||
                 lowercasedText.contains("payment due")) && !isNotABill {
            detectedType = .bill
            confidence = 0.85
        }
        // Invoice detection
        else if lowercasedText.contains("invoice") {
            detectedType = .invoice
            confidence = 0.8
        }
        // Receipt detection
        else if lowercasedText.contains("receipt") ||
                lowercasedText.contains("paid in full") ||
                lowercasedText.contains("thank you for your payment") {
            detectedType = .receipt
            confidence = 0.85
        }
        // Insurance card detection
        else if lowercasedText.contains("member id") &&
                (lowercasedText.contains("group") || lowercasedText.contains("rx bin")) {
            detectedType = .insuranceCard
            confidence = 0.9
        }
        // Lab results detection
        else if lowercasedText.contains("lab results") ||
                lowercasedText.contains("laboratory") ||
                lowercasedText.contains("test results") {
            detectedType = .labResults
            confidence = 0.8
        }
        // Prescription detection
        else if lowercasedText.contains("prescription") ||
                lowercasedText.contains("rx") && lowercasedText.contains("refill") {
            detectedType = .prescription
            confidence = 0.8
        }
        // Referral detection
        else if lowercasedText.contains("referral") ||
                lowercasedText.contains("referred to") {
            detectedType = .referral
            confidence = 0.75
        }
        // Medical records detection
        else if lowercasedText.contains("medical record") ||
                lowercasedText.contains("patient history") ||
                lowercasedText.contains("health record") {
            detectedType = .medicalRecords
            confidence = 0.75
        }
        
        // Extract key fields
        let providerName = extractProviderName(from: text)
        let patientName = extractPatientName(from: text)
        let serviceDate = extractDate(from: text)
        let totalAmount = extractAmount(from: text)
        let accountNumber = extractAccountNumber(from: text)
        
        // Generate suggested name
        var suggestedName = detectedType.rawValue
        if let provider = providerName {
            suggestedName = "\(provider) - \(detectedType.rawValue)"
        }
        if let date = serviceDate {
            suggestedName += " (\(date))"
        }
        
        return DocumentClassificationResult(
            documentType: detectedType,
            isNotABill: isNotABill,
            detectedText: text,
            suggestedName: suggestedName,
            confidence: confidence,
            providerName: providerName,
            patientName: patientName,
            serviceDate: serviceDate,
            totalAmount: totalAmount,
            accountNumber: accountNumber
        )
    }
    
    // MARK: - Field Extraction Helpers
    
    private func extractProviderName(from text: String) -> String? {
        let lines = text.components(separatedBy: .newlines)
        
        // Look for common provider indicators
        for (index, line) in lines.enumerated() {
            let lowercased = line.lowercased()
            if lowercased.contains("medical") || lowercased.contains("clinic") ||
               lowercased.contains("hospital") || lowercased.contains("health") ||
               lowercased.contains("physicians") || lowercased.contains("associates") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty && trimmed.count > 3 {
                    return trimmed
                }
            }
            // First few lines often contain provider name
            if index < 5 {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty && trimmed.count > 5 &&
                   !trimmed.lowercased().contains("@") &&
                   !trimmed.contains("www") &&
                   trimmed.range(of: #"^\d{3}"#, options: .regularExpression) == nil {
                    // Might be a name
                    if trimmed.contains("Inc") || trimmed.contains("LLC") ||
                       trimmed.contains("MD") || trimmed.contains("Dr.") {
                        return trimmed
                    }
                }
            }
        }
        return nil
    }
    
    private func extractPatientName(from text: String) -> String? {
        let lines = text.components(separatedBy: .newlines)
        
        for line in lines {
            let lowercased = line.lowercased()
            if lowercased.contains("patient:") || lowercased.contains("patient name:") {
                let parts = line.components(separatedBy: ":")
                if parts.count >= 2 {
                    return parts[1].trimmingCharacters(in: .whitespaces)
                }
            }
        }
        return nil
    }
    
    private func extractDate(from text: String) -> String? {
        let datePattern = #"\b(\d{1,2}[/-]\d{1,2}[/-]\d{2,4})\b"#
        
        if let range = text.range(of: datePattern, options: .regularExpression) {
            return String(text[range])
        }
        return nil
    }
    
    private func extractAmount(from text: String) -> String? {
        let lines = text.components(separatedBy: .newlines)
        let amountPattern = #"\$[\d,]+\.?\d{0,2}"#
        
        for line in lines {
            let lowercased = line.lowercased()
            if lowercased.contains("total") || lowercased.contains("amount due") ||
               lowercased.contains("balance") || lowercased.contains("you owe") {
                if let range = line.range(of: amountPattern, options: .regularExpression) {
                    return String(line[range])
                }
            }
        }
        
        // If no labeled amount found, look for any amount
        if let range = text.range(of: amountPattern, options: .regularExpression) {
            return String(text[range])
        }
        return nil
    }
    
    private func extractAccountNumber(from text: String) -> String? {
        let lines = text.components(separatedBy: .newlines)
        
        for line in lines {
            let lowercased = line.lowercased()
            if lowercased.contains("account") || lowercased.contains("acct") {
                let numberPattern = #"\b\d{6,15}\b"#
                if let range = line.range(of: numberPattern, options: .regularExpression) {
                    return String(line[range])
                }
            }
        }
        return nil
    }
    
    // MARK: - Save Document
    
    private func saveDocument() {
        guard let image = selectedImage else { return }
        
        // Generate unique filename
        let fileName = "doc_\(UUID().uuidString).jpg"
        
        // Save image to documents directory
        if let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let fileURL = documentsPath.appendingPathComponent(fileName)
            if let imageData = image.jpegData(compressionQuality: 0.8) {
                try? imageData.write(to: fileURL)
            }
        }
        
        // Create thumbnail
        let thumbnailData = createThumbnail(from: image)
        
        // Create document
        let document = ScannedDocument(
            patientId: appState.selectedPatientId,
            documentType: documentType,
            name: documentName,
            notes: documentNotes.isEmpty ? nil : documentNotes,
            localFileName: fileName,
            thumbnailData: thumbnailData,
            pageCount: 1,
            fileSize: Int(image.jpegData(compressionQuality: 0.8)?.count ?? 0),
            fullText: classificationResult?.detectedText,
            ocrProcessed: true
        )
        
        // Save to data service
        patientDataService.saveDocument(document)
        
        dismiss()
    }
    
    private func createThumbnail(from image: UIImage) -> Data? {
        let maxSize: CGFloat = 150
        let scale = min(maxSize / image.size.width, maxSize / image.size.height)
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        
        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        image.draw(in: CGRect(origin: .zero, size: newSize))
        let thumbnail = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return thumbnail?.jpegData(compressionQuality: 0.6)
    }
}

// MARK: - Document Source Button

struct DocumentSourceButton: View {
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

// MARK: - Document Camera View

struct DocumentCameraView: UIViewControllerRepresentable {
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
        let parent: DocumentCameraView
        
        init(_ parent: DocumentCameraView) {
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

// MARK: - Document Photo Picker View

struct DocumentPhotoPickerView: UIViewControllerRepresentable {
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
        let parent: DocumentPhotoPickerView
        
        init(_ parent: DocumentPhotoPickerView) {
            self.parent = parent
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.dismiss()
            
            guard let result = results.first else { return }
            
            result.itemProvider.loadObject(ofClass: UIImage.self) { object, error in
                if let image = object as? UIImage {
                    DispatchQueue.main.async {
                        self.parent.onSelect(image)
                    }
                }
            }
        }
    }
}

// MARK: - Document File Picker View

struct DocumentFilePickerView: UIViewControllerRepresentable {
    let onSelect: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.image, .pdf])
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: DocumentFilePickerView
        
        init(_ parent: DocumentFilePickerView) {
            self.parent = parent
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            
            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing { url.stopAccessingSecurityScopedResource() }
            }
            
            if url.pathExtension.lowercased() == "pdf" {
                if let image = renderPDFToImage(url: url) {
                    parent.onSelect(image)
                }
            } else if let data = try? Data(contentsOf: url),
                      let image = UIImage(data: data) {
                parent.onSelect(image)
            }
        }
        
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.dismiss()
        }
        
        private func renderPDFToImage(url: URL) -> UIImage? {
            guard let document = CGPDFDocument(url as CFURL),
                  let page = document.page(at: 1) else { return nil }
            
            let pageRect = page.getBoxRect(.mediaBox)
            let scale: CGFloat = 2.0
            let size = CGSize(width: pageRect.width * scale, height: pageRect.height * scale)
            
            return UIGraphicsImageRenderer(size: size).image { ctx in
                UIColor.white.setFill()
                ctx.fill(CGRect(origin: .zero, size: size))
                
                ctx.cgContext.translateBy(x: 0, y: size.height)
                ctx.cgContext.scaleBy(x: scale, y: -scale)
                ctx.cgContext.drawPDFPage(page)
            }
        }
    }
}
