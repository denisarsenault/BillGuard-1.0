//
//  BillScannerView.swift
//  BillGuard
//
//  Scan medical bills with movable selection boxes for different sections
//

import SwiftUI
import VisionKit
import Vision
import PhotosUI

// MARK: - Provider Bill Template Types
// Defined here so BillScannerView.swift compiles independently of separate model files.

enum BillFormat: String, Codable, CaseIterable {
    case standard              = "Standard"
    case accountStatement      = "Account Statement"
    case explanationOfBenefits = "Explanation of Benefits"
    case custom                = "Custom"

    var icon: String {
        switch self {
        case .standard:              return "doc.text"
        case .accountStatement:      return "tablecells"
        case .explanationOfBenefits: return "doc.badge.ellipsis"
        case .custom:                return "wrench.and.screwdriver"
        }
    }
}

struct ProcedureColumnLayout: Codable, Equatable {
    var chargesColumnKeywords:    [String] = ["charges", "debits", "billed", "amount"]
    var insurancePendingKeywords: [String] = ["insurance pending", "ins pending", "pending"]
    var paymentsColumnKeywords:   [String] = ["payments", "credits", "paid", "payment"]
    var patientAmountKeywords:    [String] = ["patient amount", "patient", "you owe", "balance"]
    var visitTotalLabels:         [String] = ["visit total", "---- visit total", "subtotal"]
    var voucherLabels:            [String] = ["voucher:", "voucher #", "claim #", "visit #"]
    var accountingRowKeywords:    [String] = [
        "payment", "adjustment", "transfer", "credit card", "self pay",
        "mastercard", "visa", "check", "write off", "write-off",
        "courtesy", "refund", "collection", "contractual"
    ]
    var useColumnPositionForCharge: Bool = false
    var chargesColumnPosition:  Int = 45
    var paymentsColumnPosition: Int = 60
    var patientAmountPosition:  Int = 75
}

struct ScanBoxRect: Codable, Equatable {
    var x: Double; var y: Double; var width: Double; var height: Double
    init(x: Double = 0, y: Double = 0, width: Double = 1, height: Double = 0.25) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
}

// MARK: - Per-Provider Scan Layout

/// The four section boxes for one provider's bill layout. `x`/`y` are box centers,
/// `width`/`height` are box sizes — all normalized 0–1 (matching `SelectionBox`).
struct SavedScanLayout: Codable, Equatable {
    var displayName: String
    var provider:  ScanBoxRect
    var patient:   ScanBoxRect
    var insurance: ScanBoxRect
    var procedure: ScanBoxRect
}

/// Persists scan-box layouts per provider in UserDefaults, so positioning a bill
/// once for a provider can be auto-applied on future scans of that provider.
enum ScanLayoutStore {
    private static let mapKey  = "ProviderScanLayouts_v1"
    private static let lastKey = "ProviderScanLayouts_lastUsed_v1"

    static func key(for provider: String) -> String {
        provider.lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func all() -> [String: SavedScanLayout] {
        guard let data = UserDefaults.standard.data(forKey: mapKey),
              let map  = try? JSONDecoder().decode([String: SavedScanLayout].self, from: data)
        else { return [:] }
        return map
    }

    /// Best layout for a provider name: exact key first, then fuzzy containment.
    static func layout(for provider: String) -> SavedScanLayout? {
        let k = key(for: provider)
        guard !k.isEmpty else { return nil }
        let map = all()
        if let exact = map[k] { return exact }
        return map.first(where: { k.contains($0.key) || $0.key.contains(k) })?.value
    }

    static func save(_ layout: SavedScanLayout, for provider: String) {
        let k = key(for: provider)
        guard !k.isEmpty else { return }
        var map = all()
        map[k] = layout
        if let data = try? JSONEncoder().encode(map) {
            UserDefaults.standard.set(data, forKey: mapKey)
        }
        UserDefaults.standard.set(provider, forKey: lastKey)
    }

    static func savedLayouts() -> [SavedScanLayout] {
        all().values.sorted { $0.displayName.lowercased() < $1.displayName.lowercased() }
    }

    static var lastUsedLayout: SavedScanLayout? {
        guard let name = UserDefaults.standard.string(forKey: lastKey) else { return nil }
        return layout(for: name)
    }
}

struct ProviderBillTemplate: Codable, Identifiable, Equatable {
    var id:            UUID   = UUID()
    var displayName:   String
    var matchKeywords: [String]
    var billFormat:    BillFormat = .standard
    var procedureColumnLayout: ProcedureColumnLayout?
    var providerBoxPosition:   ScanBoxRect? = nil
    var patientBoxPosition:    ScanBoxRect? = nil
    var insuranceBoxPosition:  ScanBoxRect? = nil
    var procedureBoxPosition:  ScanBoxRect? = nil
    var dateCreated: Date   = Date()
    var lastUsed:    Date   = Date()
    var scanCount:   Int    = 0
    var notes:       String = ""
    static func == (lhs: ProviderBillTemplate, rhs: ProviderBillTemplate) -> Bool { lhs.id == rhs.id }
}

// MARK: - Bill Scanner View

struct BillScannerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var patientDataService: PatientDataService
    @EnvironmentObject var appState: AppState
    
    @State private var sourceType: SourceType = .camera
    @State private var capturedImage: UIImage?
    @State private var showingImagePicker = false
    @State private var showingDocumentPicker = false
    @State private var showingCamera = false
    
    // Extracted text from current page regions
    @State private var patientText = ""
    @State private var providerText = ""
    @State private var insuranceText = ""
    @State private var procedureText = ""
    
    // Multi-page accumulated text (survives camera re-opens)
    @State private var accumulatedPatientText = ""
    @State private var accumulatedProviderText = ""
    @State private var accumulatedInsuranceText = ""
    @State private var accumulatedProcedureText = ""
    @State private var pageCount = 1
    
    // Processing state
    @State private var isProcessing = false
    @State private var showingReview = false
    @State private var saveResult: BillSaveResult = .none

    /// Box layout used for the current scan — saved against the detected provider.
    @State private var usedLayout: SavedScanLayout?
    
    enum SourceType: String, CaseIterable {
        case camera = "Camera"
        case photoLibrary = "Photo Library"
        case files = "Files"
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let image = capturedImage {
                    // Show image with selection boxes
                    BillRegionSelector(
                        image: image,
                        patientText: $patientText,
                        providerText: $providerText,
                        insuranceText: $insuranceText,
                        procedureText: $procedureText,
                        isProcessing: $isProcessing,
                        accumulatedPatientText: $accumulatedPatientText,
                        accumulatedProviderText: $accumulatedProviderText,
                        accumulatedInsuranceText: $accumulatedInsuranceText,
                        accumulatedProcedureText: $accumulatedProcedureText,
                        pageCount: $pageCount,
                        showingReview: $showingReview,
                        usedLayout: $usedLayout
                    )
                } else {
                    // Source selection
                    sourceSelectionView
                }
            }
            .navigationTitle("Scan Bill")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                if capturedImage != nil {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Reset") {
                            capturedImage = nil
                            patientText = ""
                            providerText = ""
                            insuranceText = ""
                            procedureText = ""
                            accumulatedPatientText = ""
                            accumulatedProviderText = ""
                            accumulatedInsuranceText = ""
                            accumulatedProcedureText = ""
                            pageCount = 1
                        }
                    }
                }
            }
            .fullScreenCover(isPresented: $showingCamera) {
                SmartDocumentScanner(capturedImage: $capturedImage)
            }
            .sheet(isPresented: $showingImagePicker) {
                ImagePicker(image: $capturedImage)
            }
            .sheet(isPresented: $showingDocumentPicker) {
                DocumentPicker(image: $capturedImage)
            }
            .sheet(isPresented: $showingReview) {
                BillReviewView(
                    patientText: accumulatedPatientText,
                    providerText: accumulatedProviderText,
                    insuranceText: accumulatedInsuranceText,
                    procedureText: accumulatedProcedureText,
                    scannedImage: capturedImage,
                    pageCount: pageCount,
                    saveResult: $saveResult,
                    usedLayout: usedLayout
                )
                .environmentObject(patientDataService)
                .environmentObject(appState)
            }
            .onChange(of: saveResult) { _, result in
                guard result != .none else { return }
                
                // Close the review sheet
                showingReview = false
                
                // Act after sheet closes
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    switch result {
                    case .scanMore:
                        // Reset for next bill scan
                        capturedImage = nil
                        patientText = ""
                        providerText = ""
                        insuranceText = ""
                        procedureText = ""
                        accumulatedPatientText = ""
                        accumulatedProviderText = ""
                        accumulatedInsuranceText = ""
                        accumulatedProcedureText = ""
                        pageCount = 1
                        saveResult = .none
                        
                    case .done:
                        // Navigate to Bills tab, then dismiss scanner
                        saveResult = .none
                        dismiss()
                        // Navigate after dismiss completes so tab switch sticks
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            appState.selectedTab = 1  // Bills tab
                        }
                        
                    case .none:
                        break
                    }
                }
            }
            .loadingOverlay(isLoading: isProcessing, message: "Extracting text...", style: .ring)
            .onReceive(NotificationCenter.default.publisher(for: .scanNextPage)) { _ in
                capturedImage = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    showingCamera = true
                }
            }
        }
    }
    
    private var sourceSelectionView: some View {
        VStack(spacing: 30) {
            Spacer()
            
            Image(systemName: "doc.text.viewfinder")
                .font(.system(size: 80))
                .foregroundColor(.accentColor)
            
            Text("Scan a Medical Bill")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Choose how to capture your bill")
                .font(.body)
                .foregroundColor(.secondary)
            
            VStack(spacing: 16) {
                // Camera option
                Button {
                    showingCamera = true
                } label: {
                    HStack {
                        Image(systemName: "camera.fill")
                            .font(.title2)
                            .frame(width: 40)
                        VStack(alignment: .leading) {
                            Text("Take Photo")
                                .font(.headline)
                            Text("Use camera to capture bill")
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
                
                // Photo Library option
                Button {
                    showingImagePicker = true
                } label: {
                    HStack {
                        Image(systemName: "photo.on.rectangle")
                            .font(.title2)
                            .frame(width: 40)
                        VStack(alignment: .leading) {
                            Text("Photo Library")
                                .font(.headline)
                            Text("Choose from saved photos")
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
                
                // Files option
                Button {
                    showingDocumentPicker = true
                } label: {
                    HStack {
                        Image(systemName: "folder.fill")
                            .font(.title2)
                            .frame(width: 40)
                        VStack(alignment: .leading) {
                            Text("Files")
                                .font(.headline)
                            Text("Import from Files app")
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
            .padding(.horizontal, 30)
            .padding(.top, 20)
            
            Spacer()
        }
    }
}

// MARK: - Bill Region Selector

struct BillRegionSelector: View {
    let image: UIImage
    @Binding var patientText: String
    @Binding var providerText: String
    @Binding var insuranceText: String
    @Binding var procedureText: String
    @Binding var isProcessing: Bool
    
    // Multi-page bindings (owned by parent BillScannerView)
    @Binding var accumulatedPatientText: String
    @Binding var accumulatedProviderText: String
    @Binding var accumulatedInsuranceText: String
    @Binding var accumulatedProcedureText: String
    @Binding var pageCount: Int
    @Binding var showingReview: Bool

    /// The box layout used for this scan — surfaced to the parent so it can be
    /// saved against the detected provider once parsing identifies them.
    @Binding var usedLayout: SavedScanLayout?

    // Selection box positions (normalized 0-1)
    // Layout: Provider full-width across top, Patient (left) + Insurance (right) below, Procedures at bottom
    @State private var providerBox = SelectionBox(
        position: CGPoint(x: 0.5, y: 0.08),
        size: CGSize(width: 0.95, height: 0.12)
    )
    @State private var patientBox = SelectionBox(
        position: CGPoint(x: 0.25, y: 0.24),
        size: CGSize(width: 0.45, height: 0.15)
    )
    @State private var insuranceBox = SelectionBox(
        position: CGPoint(x: 0.75, y: 0.24),
        size: CGSize(width: 0.45, height: 0.15)
    )
    @State private var procedureBox = SelectionBox(
        position: CGPoint(x: 0.5, y: 0.62),
        size: CGSize(width: 1.0, height: 0.48)
    )
    
    @State private var activeBox: BoxType?
    @State private var showingMorePagesPrompt = false

    // Section enable/disable toggles
    @State private var showProviderBox   = true
    @State private var showPatientBox    = true
    @State private var showInsuranceBox  = true
    @State private var showProcedureBox  = true
    
    // Zoom and pan state
    @State private var zoomScale: CGFloat = 1.0
    @State private var lastZoomScale: CGFloat = 1.0
    @State private var panOffset: CGSize = .zero
    @State private var lastPanOffset: CGSize = .zero

    // Warns when the Provider box appears to include a "pay by card" billing box.
    @State private var providerHasCardBox = false
    @State private var cardBoxCheckTask: Task<Void, Never>? = nil

    enum BoxType: String {
        case patient = "Patient Info"
        case provider = "Provider Info"
        case insurance = "Insurance"
        case procedure = "Procedures"
    }
    
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Instructions
                instructionsBar

                // Warning: Provider box appears to include a "pay by card" box
                if providerHasCardBox && showProviderBox {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.yellow)
                        Text("The Provider box includes a \u{201C}pay by card\u{201D} box — drag its edge in to cover only the facility name/address.")
                            .font(.caption)
                            .foregroundColor(.white)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.yellow.opacity(0.18))
                    .overlay(Rectangle().fill(Color.yellow).frame(width: 3), alignment: .leading)
                    .transition(.opacity)
                }

                // Image with selection boxes - zoomable
                ZStack {
                    // The bill image with zoom and pan
                    GeometryReader { imageGeometry in
                        let imageFrame = calculateImageFrame(in: imageGeometry.size)
                        
                        ZStack {
                            // Zoomable/pannable image
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: imageFrame.size.width, height: imageFrame.size.height)
                                .position(x: imageGeometry.size.width / 2, y: imageGeometry.size.height / 2)
                            
                            // Selection boxes overlay
                            ZStack {
                                // Patient box (Blue)
                                if showPatientBox {
                                    DraggableBox(
                                        box: $patientBox,
                                        containerSize: imageFrame.size,
                                        offset: imageFrame.origin,
                                        color: .blue,
                                        label: "Patient",
                                        isActive: activeBox == .patient,
                                        zoomScale: zoomScale
                                    )
                                    .onTapGesture { activeBox = .patient }
                                    .transition(.opacity.combined(with: .scale))
                                }

                                // Provider box (Green)
                                if showProviderBox {
                                    DraggableBox(
                                        box: $providerBox,
                                        containerSize: imageFrame.size,
                                        offset: imageFrame.origin,
                                        color: .green,
                                        label: "Provider",
                                        isActive: activeBox == .provider,
                                        zoomScale: zoomScale
                                    )
                                    .onTapGesture { activeBox = .provider }
                                    .transition(.opacity.combined(with: .scale))
                                }

                                // Insurance box (Purple)
                                if showInsuranceBox {
                                    DraggableBox(
                                        box: $insuranceBox,
                                        containerSize: imageFrame.size,
                                        offset: imageFrame.origin,
                                        color: .purple,
                                        label: "Insurance",
                                        isActive: activeBox == .insurance,
                                        zoomScale: zoomScale
                                    )
                                    .onTapGesture { activeBox = .insurance }
                                    .transition(.opacity.combined(with: .scale))
                                }

                                // Procedure box (Orange)
                                if showProcedureBox {
                                    DraggableBox(
                                        box: $procedureBox,
                                        containerSize: imageFrame.size,
                                        offset: imageFrame.origin,
                                        color: .orange,
                                        label: "Procedures",
                                        isActive: activeBox == .procedure,
                                        zoomScale: zoomScale
                                    )
                                    .onTapGesture { activeBox = .procedure }
                                    .transition(.opacity.combined(with: .scale))
                                }
                            }
                            .animation(.easeInOut(duration: 0.2), value: showProviderBox)
                            .animation(.easeInOut(duration: 0.2), value: showPatientBox)
                            .animation(.easeInOut(duration: 0.2), value: showInsuranceBox)
                            .animation(.easeInOut(duration: 0.2), value: showProcedureBox)
                        }
                        .coordinateSpace(name: "billImageArea")
                        .scaleEffect(zoomScale)
                        .offset(panOffset)
                        .gesture(
                            SimultaneousGesture(
                                // Pinch to zoom
                                MagnificationGesture()
                                    .onChanged { value in
                                        let newScale = lastZoomScale * value
                                        zoomScale = min(max(newScale, 1.0), 5.0) // Limit zoom 1x to 5x
                                    }
                                    .onEnded { _ in
                                        lastZoomScale = zoomScale
                                        // Reset pan if zoomed out
                                        if zoomScale <= 1.0 {
                                            withAnimation(.easeOut(duration: 0.2)) {
                                                panOffset = .zero
                                                lastPanOffset = .zero
                                            }
                                        }
                                    },
                                // Pan when zoomed
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
                            // Double tap to reset zoom
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
                }
                .background(Color.black)
                .clipped()
                
                // Zoom indicator
                if zoomScale > 1.0 {
                    HStack {
                        Image(systemName: "magnifyingglass")
                        Text("\(Int(zoomScale * 100))%")
                        Spacer()
                        Button("Reset") {
                            withAnimation(.easeOut(duration: 0.2)) {
                                zoomScale = 1.0
                                lastZoomScale = 1.0
                                panOffset = .zero
                                lastPanOffset = .zero
                            }
                        }
                        .font(.caption)
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                    .padding(.vertical, 6)
                    .background(Color("BrandDeepNavy"))
                }
                
                // Bottom controls
                bottomControls
            }
        }
        .alert("More Pages?", isPresented: $showingMorePagesPrompt) {
            Button("Scan Next Page") {
                pageCount += 1
                // Signal parent to reopen camera for another page
                NotificationCenter.default.post(name: .scanNextPage, object: nil)
            }
            Button("Done — Review Bill") {
                showingReview = true
            }
        } message: {
            Text("Page \(pageCount) extracted. Does this bill have additional pages to scan?")
        }
        .onAppear {
            // Auto-apply the most recently used provider layout as a starting point.
            // The user can still adjust, switch via the Layouts menu, or Reset.
            if let last = ScanLayoutStore.lastUsedLayout {
                apply(last)
            }
            scheduleCardBoxCheck()
        }
        .onChange(of: providerBox.position) { _, _ in scheduleCardBoxCheck() }
        .onChange(of: providerBox.size) { _, _ in scheduleCardBoxCheck() }
        .onChange(of: showProviderBox) { _, on in
            if on { scheduleCardBoxCheck() } else { providerHasCardBox = false }
        }
    }

    /// Debounced check: fast-OCR the current Provider box region and flag it if it
    /// contains "pay by card" billing-box text, so we can hint the user to exclude it.
    private func scheduleCardBoxCheck() {
        cardBoxCheckTask?.cancel()
        guard showProviderBox else { providerHasCardBox = false; return }
        let box = providerBox
        let img = image
        cardBoxCheckTask = Task {
            try? await Task.sleep(nanoseconds: 450_000_000)   // debounce drags
            if Task.isCancelled { return }
            let detected = await Self.regionContainsCardBox(in: img, box: box)
            if Task.isCancelled { return }
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.2)) { providerHasCardBox = detected }
            }
        }
    }

    /// Fast OCR of the box region; true if ≥2 distinctive billing-box terms appear.
    private static func regionContainsCardBox(in image: UIImage, box: SelectionBox) async -> Bool {
        let oriented: UIImage
        if image.imageOrientation != .up,
           let cg = DocumentImageEnhancer.normalizeOrientation(image) {
            oriented = UIImage(cgImage: cg)
        } else {
            oriented = image
        }
        guard let cg = oriented.cgImage else { return false }
        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        let left = max(0, (box.position.x - box.size.width / 2) * w)
        let top  = max(0, (box.position.y - box.size.height / 2) * h)
        let rect = CGRect(x: left, y: top,
                          width:  min(box.size.width * w, w - left),
                          height: min(box.size.height * h, h - top))
        guard rect.width > 1, rect.height > 1, let cropped = cg.cropping(to: rect) else { return false }

        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { req, _ in
                let text = (req.results as? [VNRecognizedTextObservation] ?? [])
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: " ")
                    .uppercased()
                let markers = ["MASTERCARD", "VISA", "CARDHOLDER", "CARD NUMBER",
                               "VERIFICATION", "EXP", "IF PAYING", "FILL OUT",
                               "CHECK CARD", "SIGNATURE"]
                let hits = markers.reduce(0) { $0 + (text.contains($1) ? 1 : 0) }
                continuation.resume(returning: hits >= 2)
            }
            request.recognitionLevel = .fast
            request.usesLanguageCorrection = false
            try? VNImageRequestHandler(cgImage: cropped, options: [:]).perform([request])
        }
    }

    private var instructionsBar: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                Text("Position boxes over each section")
                    .font(.subheadline)
                    .fontWeight(.medium)
                if pageCount > 1 {
                    Text("Page \(pageCount)")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.accentColor))
                }
            }
            Text("Pinch to zoom \u{2022} Drag boxes \u{2022} Pinch corners to resize")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(Color("BrandDeepNavy"))
    }
    
    private var bottomControls: some View {
        VStack(spacing: 12) {
            // Section toggle buttons — tap to enable / disable each box and its parsing
            HStack(spacing: 10) {
                sectionToggle(label: "Provider",   color: .green,  isOn: $showProviderBox)
                sectionToggle(label: "Patient",    color: .blue,   isOn: $showPatientBox)
                sectionToggle(label: "Insurance",  color: .purple, isOn: $showInsuranceBox)
                sectionToggle(label: "Procedures", color: .orange, isOn: $showProcedureBox)
            }
            .padding(.top, 10)
            .padding(.horizontal, 4)

            // Saved per-provider layouts — apply a remembered box arrangement
            let savedLayouts = ScanLayoutStore.savedLayouts()
            if !savedLayouts.isEmpty {
                Menu {
                    ForEach(savedLayouts, id: \.displayName) { layout in
                        Button(layout.displayName) {
                            withAnimation(.easeInOut(duration: 0.2)) { apply(layout) }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "rectangle.dashed.badge.record")
                        Text("Apply Saved Layout")
                    }
                    .font(.subheadline)
                    .foregroundColor(.accentColor)
                }
                .padding(.horizontal)
            }

            // Extract button
            Button {
                extractText()
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
    
    private func sectionToggle(label: String, color: Color, isOn: Binding<Bool>) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isOn.wrappedValue.toggle()
            }
        } label: {
            HStack(spacing: 5) {
                // Colour swatch / checkmark
                ZStack {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(isOn.wrappedValue ? color.opacity(0.25) : Color.clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(isOn.wrappedValue ? color : color.opacity(0.35), lineWidth: 2)
                        )
                        .frame(width: 16, height: 16)
                    if isOn.wrappedValue {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(color)
                    }
                }
                Text(label)
                    .font(.caption)
                    .fontWeight(isOn.wrappedValue ? .semibold : .regular)
                    .foregroundColor(isOn.wrappedValue ? .primary : .secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isOn.wrappedValue ? color.opacity(0.08) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isOn.wrappedValue ? color.opacity(0.4) : Color.secondary.opacity(0.3),
                                    lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
    
    private func calculateImageFrame(in containerSize: CGSize) -> CGRect {
        let imageAspect = image.size.width / image.size.height
        let containerAspect = containerSize.width / containerSize.height
        
        var size: CGSize
        var origin: CGPoint
        
        if imageAspect > containerAspect {
            // Image is wider - fit to width
            size = CGSize(width: containerSize.width, height: containerSize.width / imageAspect)
            origin = CGPoint(x: 0, y: (containerSize.height - size.height) / 2)
        } else {
            // Image is taller - fit to height
            size = CGSize(width: containerSize.height * imageAspect, height: containerSize.height)
            origin = CGPoint(x: (containerSize.width - size.width) / 2, y: 0)
        }
        
        return CGRect(origin: origin, size: size)
    }
    
    /// Snapshot the current four boxes as a reusable layout.
    private func currentLayout(named name: String = "") -> SavedScanLayout {
        SavedScanLayout(
            displayName: name,
            provider:  providerBox.asRect,
            patient:   patientBox.asRect,
            insurance: insuranceBox.asRect,
            procedure: procedureBox.asRect
        )
    }

    /// Apply a saved layout to the four boxes.
    private func apply(_ layout: SavedScanLayout) {
        providerBox  = SelectionBox(layout.provider)
        patientBox   = SelectionBox(layout.patient)
        insuranceBox = SelectionBox(layout.insurance)
        procedureBox = SelectionBox(layout.procedure)
    }

    private func extractText() {
        isProcessing = true

        // Remember the layout used so the parent can save it against the
        // detected provider once parsing identifies them.
        usedLayout = currentLayout()

        // Snapshot enabled state before entering the async task
        let extractPatient   = showPatientBox
        let extractProvider  = showProviderBox
        let extractInsurance = showInsuranceBox
        let extractProcedure = showProcedureBox

        Task {
            let normalizedImage = normalizeImageOrientation(image)

            // Only run OCR for sections whose box is currently enabled
            async let patient   = extractPatient
                ? recognizeText(in: normalizedImage, region: normalizedToImageRect(patientBox,   imageSize: normalizedImage.size))
                : ""
            async let provider  = extractProvider
                ? recognizeText(in: normalizedImage, region: normalizedToImageRect(providerBox,  imageSize: normalizedImage.size))
                : ""
            async let insurance = extractInsurance
                ? recognizeText(in: normalizedImage, region: normalizedToImageRect(insuranceBox, imageSize: normalizedImage.size))
                : ""
            async let procedure = extractProcedure
                ? recognizeText(in: normalizedImage, region: normalizedToImageRect(procedureBox, imageSize: normalizedImage.size))
                : ""

            let results = await (patient, provider, insurance, procedure)

            await MainActor.run {
                // Update current-page bindings (for parent view compatibility)
                patientText   = results.0
                providerText  = results.1
                insuranceText = results.2
                procedureText = results.3

                // Accumulate across pages — only update enabled sections
                if extractPatient && !results.0.isEmpty {
                    accumulatedPatientText += (accumulatedPatientText.isEmpty ? "" : "\n") + results.0
                }
                if extractProvider && !results.1.isEmpty {
                    accumulatedProviderText += (accumulatedProviderText.isEmpty ? "" : "\n") + results.1
                }
                if extractInsurance && !results.2.isEmpty {
                    accumulatedInsuranceText += (accumulatedInsuranceText.isEmpty ? "" : "\n") + results.2
                }
                if extractProcedure && !results.3.isEmpty {
                    accumulatedProcedureText += (accumulatedProcedureText.isEmpty ? "" : "\n") + results.3
                }
                
                isProcessing = false
                
                // Ask if there are more pages
                showingMorePagesPrompt = true
            }
        }
    }
    
    /// Normalize image orientation so CGImage coordinates match what's displayed
    private func normalizeImageOrientation(_ image: UIImage) -> UIImage {
        // If orientation is already up, no need to redraw
        if image.imageOrientation == .up {
            return image
        }
        
        // Redraw the image with correct orientation
        UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
        image.draw(in: CGRect(origin: .zero, size: image.size))
        let normalizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return normalizedImage ?? image
    }
    
    private func normalizedToImageRect(_ box: SelectionBox, imageSize: CGSize) -> CGRect {
        // Convert normalized box coordinates (0-1) to image pixel coordinates
        // box.position is the CENTER of the box
        // box.size is the SIZE of the box (as fraction of image)
        
        let left = (box.position.x - box.size.width / 2) * imageSize.width
        let top = (box.position.y - box.size.height / 2) * imageSize.height
        let width = box.size.width * imageSize.width
        let height = box.size.height * imageSize.height
        
        // Clamp to image bounds
        let clampedX = max(0, left)
        let clampedY = max(0, top)
        let clampedRight = min(left + width, imageSize.width)
        let clampedBottom = min(top + height, imageSize.height)
        
        return CGRect(
            x: clampedX,
            y: clampedY,
            width: max(1, clampedRight - clampedX),
            height: max(1, clampedBottom - clampedY)
        )
    }
    
    /// Recognize text with spatial row grouping — blocks at the same Y form one line.
    /// This is critical for multi-column layouts where Vision returns separate observations
    /// for "Account #:" and "ACCT-2024-78452" even though they're on the same visual line.
    /// Estimates the mean luminance of a CGImage in 0–1.
    /// Samples every 8th pixel of the green channel (fast and perceptually representative).
    private func meanLuminance(of cgImage: CGImage) -> CGFloat {
        guard let data = cgImage.dataProvider?.data,
              let ptr  = CFDataGetBytePtr(data) else { return 0.5 }
        let width    = cgImage.width
        let height   = cgImage.height
        let bpp      = cgImage.bitsPerPixel / 8   // bytes per pixel
        let rowBytes = cgImage.bytesPerRow
        let step     = 8
        var total: UInt64 = 0
        var count: UInt64 = 0
        var y = 0
        while y < height {
            var x = 0
            while x < width {
                let offset = y * rowBytes + x * bpp
                // Use green channel (index 1) as luminance proxy; works for RGB/RGBA
                total &+= UInt64(ptr[offset + min(1, bpp - 1)])
                count &+= 1
                x += step
            }
            y += step
        }
        return count > 0 ? CGFloat(total) / CGFloat(count) / 255.0 : 0.5
    }

    /// Prepares a cropped image region for OCR.
    /// If the region has a dark background (mean luma < 0.45) the image is:
    ///   1. Inverted  — turns white-on-dark into dark-on-white
    ///   2. Contrast-boosted — improves OCR accuracy on low-contrast inverted text
    private func prepareForOCR(_ cgImage: CGImage) -> CGImage {
        let luma = meanLuminance(of: cgImage)
        guard luma < 0.45 else { return cgImage }   // already light-bg — no change needed

        let ci  = CIImage(cgImage: cgImage)
        let ctx = CIContext()

        // Step 1: invert colours
        guard let invertFilter = CIFilter(name: "CIColorInvert") else { return cgImage }
        invertFilter.setValue(ci, forKey: kCIInputImageKey)
        guard let inverted = invertFilter.outputImage else { return cgImage }

        // Step 2: boost contrast so the now-dark text is crisp
        guard let contrastFilter = CIFilter(name: "CIColorControls") else { return cgImage }
        contrastFilter.setValue(inverted, forKey: kCIInputImageKey)
        contrastFilter.setValue(1.6,       forKey: kCIInputContrastKey)
        contrastFilter.setValue(0.0,        forKey: kCIInputSaturationKey)  // greyscale
        guard let boosted = contrastFilter.outputImage else { return cgImage }

        return ctx.createCGImage(boosted, from: boosted.extent) ?? cgImage
    }

    private func recognizeText(in image: UIImage, region: CGRect) async -> String {
        guard let cgImage = image.cgImage else { return "" }

        // `region` is in the image's POINT coordinate space (image.size) — the same
        // space the on-screen selection boxes are drawn in. The CGImage is in PIXELS,
        // so convert by the image's scale factor; otherwise a scale ≠ 1 (e.g. after
        // the enhance pass) makes OCR crop only a top-left fraction of the box the
        // user framed ("what I frame isn't what gets scanned").
        let scaleX = CGFloat(cgImage.width)  / max(image.size.width,  1)
        let scaleY = CGFloat(cgImage.height) / max(image.size.height, 1)
        let pixelRegion = CGRect(
            x:      region.origin.x   * scaleX,
            y:      region.origin.y   * scaleY,
            width:  region.size.width * scaleX,
            height: region.size.height * scaleY
        )

        let imageRect = CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height)
        let validRegion = pixelRegion.intersection(imageRect)
        guard !validRegion.isEmpty, validRegion.width > 0, validRegion.height > 0 else { return "" }
        guard let cropped = cgImage.cropping(to: validRegion) else { return "" }

        // Pre-process: invert dark-background regions so Vision sees dark text on white
        let croppedImage = prepareForOCR(cropped)

        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: "")
                    return
                }
                
                struct TextBlock {
                    let text: String
                    let midX: CGFloat
                    let midY: CGFloat
                    let height: CGFloat
                }
                
                let blocks: [TextBlock] = observations.compactMap { o in
                    guard let text = o.topCandidates(1).first?.string else { return nil }
                    return TextBlock(text: text, midX: o.boundingBox.midX,
                                     midY: o.boundingBox.midY, height: o.boundingBox.height)
                }
                
                // Group into rows by Y proximity (same logic as ScannerView.extractBillInfo)
                var rows: [[TextBlock]] = []
                let sorted = blocks.sorted { $0.midY > $1.midY } // top-to-bottom (Vision Y is bottom-up)
                
                for block in sorted {
                    let yTol = max(block.height * 1.0, 0.012)
                    if let rowIdx = rows.firstIndex(where: { row in
                        let avgY = row.map { $0.midY }.reduce(0, +) / CGFloat(row.count)
                        return abs(avgY - block.midY) < yTol
                    }) {
                        rows[rowIdx].append(block)
                    } else {
                        rows.append([block])
                    }
                }
                
                // Sort rows top-to-bottom, blocks within each row left-to-right
                rows.sort {
                    let avgY0 = $0.map { $0.midY }.reduce(0, +) / CGFloat($0.count)
                    let avgY1 = $1.map { $0.midY }.reduce(0, +) / CGFloat($1.count)
                    return avgY0 > avgY1
                }
                
                let lines = rows.map { row in
                    row.sorted { $0.midX < $1.midX }
                       .map { $0.text }
                       .joined(separator: "  ")
                }
                
                continuation.resume(returning: lines.joined(separator: "\n"))
            }
            
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            
            let handler = VNImageRequestHandler(cgImage: croppedImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: "")
            }
        }
    }
}

// MARK: - Selection Box Model

struct SelectionBox {
    var position: CGPoint  // Center position (normalized 0-1)
    var size: CGSize       // Size (normalized 0-1)
}

extension SelectionBox {
    var asRect: ScanBoxRect {
        ScanBoxRect(x: Double(position.x), y: Double(position.y),
                    width: Double(size.width), height: Double(size.height))
    }
    init(_ rect: ScanBoxRect) {
        self.init(position: CGPoint(x: rect.x, y: rect.y),
                  size: CGSize(width: rect.width, height: rect.height))
    }
}

// MARK: - Draggable Box View

struct DraggableBox: View {
    @Binding var box: SelectionBox
    let containerSize: CGSize
    let offset: CGPoint
    let color: Color
    let label: String
    let isActive: Bool
    var zoomScale: CGFloat = 1.0
    
    @State private var isDragging = false
    
    var body: some View {
        let boxW = box.size.width * containerSize.width
        let boxH = box.size.height * containerSize.height
        let boxMidX = offset.x + box.position.x * containerSize.width
        let boxMidY = offset.y + box.position.y * containerSize.height
        
        ZStack {
            // Box background
            Rectangle()
                .fill(color.opacity(0.15))
                .overlay(
                    Rectangle()
                        .stroke(color, lineWidth: isActive ? 3 : 2)
                )
            
            // Label - hide if box is too small
            if boxH > 30 {
                VStack {
                    Text(label)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(color)
                        .cornerRadius(3)
                    Spacer()
                }
                .padding(.top, 2)
            }
            
            // Resize handles at corners and edges
            if isActive {
                ResizeHandles(box: $box, containerSize: containerSize, color: color, zoomScale: zoomScale)
            }
        }
        .frame(width: max(20, boxW), height: max(10, boxH))
        .position(x: boxMidX, y: boxMidY)
        .gesture(
            DragGesture(coordinateSpace: .named("billImageArea"))
                .onChanged { value in
                    isDragging = true
                    // value.location is in the "billImageArea" coordinate space
                    let adjustedX = (value.location.x - offset.x) / containerSize.width
                    let adjustedY = (value.location.y - offset.y) / containerSize.height
                    
                    // Clamp to bounds
                    box.position.x = max(box.size.width / 2, min(1 - box.size.width / 2, adjustedX))
                    box.position.y = max(box.size.height / 2, min(1 - box.size.height / 2, adjustedY))
                }
                .onEnded { _ in
                    isDragging = false
                }
        )
    }
}

// MARK: - Resize Handles

struct ResizeHandles: View {
    @Binding var box: SelectionBox
    let containerSize: CGSize
    let color: Color
    var zoomScale: CGFloat = 1.0
    
    var body: some View {
        GeometryReader { geometry in
            // Adjust handle size based on zoom - smaller when zoomed in
            let handleSize: CGFloat = max(16, 24 / zoomScale)
            
            // Corner handles
            ForEach(Corner.allCases, id: \.self) { corner in
                Circle()
                    .fill(color)
                    .frame(width: handleSize, height: handleSize)
                    .overlay(
                        Circle()
                            .stroke(Color.white, lineWidth: 2)
                    )
                    .position(cornerPosition(corner, in: geometry.size))
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                resizeBox(corner: corner, to: value.location, in: geometry.size)
                            }
                    )
            }
            
            // Edge handles for more precise control (top and bottom edges for height adjustment)
            ForEach(Edge.allCases, id: \.self) { edge in
                Capsule()
                    .fill(color.opacity(0.8))
                    .frame(
                        width: edge.isHorizontal ? min(40, geometry.size.width * 0.3) : handleSize * 0.6,
                        height: edge.isHorizontal ? handleSize * 0.6 : min(40, geometry.size.height * 0.3)
                    )
                    .overlay(
                        Capsule()
                            .stroke(Color.white, lineWidth: 1)
                    )
                    .position(edgePosition(edge, in: geometry.size))
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                resizeBoxEdge(edge: edge, to: value.location, in: geometry.size)
                            }
                    )
            }
        }
    }
    
    enum Corner: CaseIterable {
        case topLeft, topRight, bottomLeft, bottomRight
    }
    
    enum Edge: CaseIterable {
        case top, bottom, left, right
        
        var isHorizontal: Bool {
            self == .top || self == .bottom
        }
    }
    
    private func cornerPosition(_ corner: Corner, in size: CGSize) -> CGPoint {
        switch corner {
        case .topLeft: return CGPoint(x: 0, y: 0)
        case .topRight: return CGPoint(x: size.width, y: 0)
        case .bottomLeft: return CGPoint(x: 0, y: size.height)
        case .bottomRight: return CGPoint(x: size.width, y: size.height)
        }
    }
    
    private func edgePosition(_ edge: Edge, in size: CGSize) -> CGPoint {
        switch edge {
        case .top: return CGPoint(x: size.width / 2, y: 0)
        case .bottom: return CGPoint(x: size.width / 2, y: size.height)
        case .left: return CGPoint(x: 0, y: size.height / 2)
        case .right: return CGPoint(x: size.width, y: size.height / 2)
        }
    }
    
    private func resizeBox(corner: Corner, to location: CGPoint, in size: CGSize) {
        // Allow very small minimum - just 2% for single line text capture
        let minWidth: CGFloat = 0.02
        let minHeight: CGFloat = 0.01  // Can be very thin for single line
        
        // Calculate new normalized coordinates
        let localX = location.x / size.width
        let localY = location.y / size.height
        
        var newPosition = box.position
        var newSize = box.size
        
        switch corner {
        case .topLeft:
            let right = box.position.x + box.size.width / 2
            let bottom = box.position.y + box.size.height / 2
            let newLeft = box.position.x - box.size.width / 2 + localX * box.size.width
            let newTop = box.position.y - box.size.height / 2 + localY * box.size.height
            newSize.width = max(minWidth, right - newLeft)
            newSize.height = max(minHeight, bottom - newTop)
            newPosition.x = right - newSize.width / 2
            newPosition.y = bottom - newSize.height / 2
            
        case .topRight:
            let left = box.position.x - box.size.width / 2
            let bottom = box.position.y + box.size.height / 2
            let newRight = box.position.x - box.size.width / 2 + localX * box.size.width
            let newTop = box.position.y - box.size.height / 2 + localY * box.size.height
            newSize.width = max(minWidth, newRight - left)
            newSize.height = max(minHeight, bottom - newTop)
            newPosition.x = left + newSize.width / 2
            newPosition.y = bottom - newSize.height / 2
            
        case .bottomLeft:
            let right = box.position.x + box.size.width / 2
            let top = box.position.y - box.size.height / 2
            let newLeft = box.position.x - box.size.width / 2 + localX * box.size.width
            let newBottom = box.position.y - box.size.height / 2 + localY * box.size.height
            newSize.width = max(minWidth, right - newLeft)
            newSize.height = max(minHeight, newBottom - top)
            newPosition.x = right - newSize.width / 2
            newPosition.y = top + newSize.height / 2
            
        case .bottomRight:
            let left = box.position.x - box.size.width / 2
            let top = box.position.y - box.size.height / 2
            let newRight = box.position.x - box.size.width / 2 + localX * box.size.width
            let newBottom = box.position.y - box.size.height / 2 + localY * box.size.height
            newSize.width = max(minWidth, newRight - left)
            newSize.height = max(minHeight, newBottom - top)
            newPosition.x = left + newSize.width / 2
            newPosition.y = top + newSize.height / 2
        }
        
        // Clamp to bounds
        newPosition.x = max(newSize.width / 2, min(1 - newSize.width / 2, newPosition.x))
        newPosition.y = max(newSize.height / 2, min(1 - newSize.height / 2, newPosition.y))
        
        box.position = newPosition
        box.size = newSize
    }
    
    private func resizeBoxEdge(edge: Edge, to location: CGPoint, in size: CGSize) {
        let minWidth: CGFloat = 0.02
        let minHeight: CGFloat = 0.01
        
        var newPosition = box.position
        var newSize = box.size
        
        switch edge {
        case .top:
            let bottom = box.position.y + box.size.height / 2
            let newTop = box.position.y - box.size.height / 2 + (location.y / size.height) * box.size.height
            newSize.height = max(minHeight, bottom - newTop)
            newPosition.y = bottom - newSize.height / 2
            
        case .bottom:
            let top = box.position.y - box.size.height / 2
            let newBottom = box.position.y - box.size.height / 2 + (location.y / size.height) * box.size.height
            newSize.height = max(minHeight, newBottom - top)
            newPosition.y = top + newSize.height / 2
            
        case .left:
            let right = box.position.x + box.size.width / 2
            let newLeft = box.position.x - box.size.width / 2 + (location.x / size.width) * box.size.width
            newSize.width = max(minWidth, right - newLeft)
            newPosition.x = right - newSize.width / 2
            
        case .right:
            let left = box.position.x - box.size.width / 2
            let newRight = box.position.x - box.size.width / 2 + (location.x / size.width) * box.size.width
            newSize.width = max(minWidth, newRight - left)
            newPosition.x = left + newSize.width / 2
        }
        
        // Clamp to bounds
        newPosition.x = max(newSize.width / 2, min(1 - newSize.width / 2, newPosition.x))
        newPosition.y = max(newSize.height / 2, min(1 - newSize.height / 2, newPosition.y))
        
        box.position = newPosition
        box.size = newSize
    }
}

// MARK: - Parsed Line Item (editable in review)

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

// MARK: - Bill Save Result

enum BillSaveResult: Equatable {
    case none       // No save happened yet
    case scanMore   // Save succeeded, user wants to scan another bill
    case done       // Save succeeded, user is done
}

// MARK: - Bill Review View

struct BillReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var patientDataService: PatientDataService
    @EnvironmentObject var appState: AppState
    
    let patientText: String
    let providerText: String
    let insuranceText: String
    let procedureText: String
    let scannedImage: UIImage?
    let pageCount: Int
    
    /// Binding to parent — set to .scanMore or .done to trigger dismiss + action
    @Binding var saveResult: BillSaveResult

    /// Box layout used for this scan — saved against the detected provider.
    var usedLayout: SavedScanLayout? = nil

    // Parsed patient fields
    @State private var patientName = ""
    @State private var accountNumber = ""
    @State private var dateOfBirth = ""
    @State private var patientAddress = ""
    @State private var mrn = ""
    @State private var dischargeDate = ""
    @State private var admitDate = ""
    
    // Provider template — detected after parseProviderFields()
    @State private var detectedTemplate: ProviderBillTemplate? = nil

    // Parsed provider fields
    @State private var providerName = ""
    @State private var providerAddress = ""
    @State private var providerPhone = ""
    @State private var providerFax = ""
    @State private var providerEmail = ""
    @State private var providerWebsite = ""
    @State private var providerNPI = ""
    @State private var providerTaxId = ""
    @State private var providerLicense = ""
    
    // Parsed insurance fields
    @State private var insuranceCarrier = ""
    @State private var policyNumber = ""
    @State private var memberId = ""
    @State private var groupNumber = ""
    @State private var insurancePlanType = ""
    
    // Bill details
    @State private var serviceDate = Date()
    @State private var billedAmount: String = ""
    
    // Financial summary (parsed from OCR)
    @State private var totalCharges: String = ""
    @State private var insuranceAdjustment: String = ""
    @State private var insurancePaid: String = ""
    @State private var amountDue: String = ""
    
    // Line items
    @State private var lineItems: [ParsedLineItem] = []
    @State private var showingAddLineItem = false
    
    // Save state
    @State private var isSaving = false
    @State private var rawOCRCopied = false

    @State private var savedClaimId: String?
    
    // Duplicate detection
    @State private var showingDuplicateAlert = false
    @State private var duplicateClaim: Claim?
    @State private var pendingClaim: Claim?
    
    // Code scanner integration
    @State private var showingCodeScanner = false
    @State private var pendingProviderId: String?
    
    // Patient resolution
    @State private var showingPatientPrompt = false
    @State private var resolvedPatientId: String?
    @State private var matchedExistingPatient: Patient?
    @State private var showingNoPatientAlert = false
    
    var body: some View {
        NavigationStack {
            Form {
                // Insurance Information — FIRST
                Section {
                    fieldRow("Insurance Carrier", $insuranceCarrier, icon: "shield")
                    fieldRow("Policy #", $policyNumber, icon: "number")
                    fieldRow("Member ID", $memberId, icon: "person.badge.key")
                    fieldRow("Group #", $groupNumber, icon: "person.3")
                    fieldRow("Plan Type", $insurancePlanType, icon: "doc.text")
                    fieldRow("MRN", $mrn, icon: "cross.case")
                    fieldRow("Discharge Date", $dischargeDate, icon: "calendar.badge.minus")
                } header: {
                    Label("Insurance", systemImage: "shield.fill").foregroundColor(.purple)
                }
                
                // Provider Information
                Section {
                    fieldRow("Facility/Provider", $providerName, icon: "building.2")
                    fieldRow("Address", $providerAddress, icon: "mappin.circle")
                    fieldRow("Phone", $providerPhone, icon: "phone")
                    fieldRow("Fax", $providerFax, icon: "fax")
                    fieldRow("Email", $providerEmail, icon: "envelope")
                    fieldRow("Website", $providerWebsite, icon: "globe")
                    fieldRow("NPI", $providerNPI, icon: "number")
                    fieldRow("Tax ID / EIN", $providerTaxId, icon: "doc.text")
                    fieldRow("License #", $providerLicense, icon: "creditcard")
                } header: {
                    Label("Provider", systemImage: "building.2.fill").foregroundColor(.green)
                }
                
                // Patient Information
                Section {
                    fieldRow("Patient Name",    $patientName,    icon: "person")
                    fieldRow("Account #",       $accountNumber,  icon: "number.circle")
                    fieldRow("MRN",             $mrn,            icon: "cross.case")
                    fieldRow("Date of Birth",   $dateOfBirth,    icon: "gift")
                    fieldRow("Patient Address", $patientAddress, icon: "house")
                    fieldRow("Admit Date",      $admitDate,      icon: "calendar")
                    fieldRow("Discharge Date",  $dischargeDate,  icon: "calendar.badge.checkmark")
                } header: {
                    Label("Patient", systemImage: "person.fill").foregroundColor(.blue)
                }

                // Bill Details
                Section {
                    DatePicker("Service Date", selection: $serviceDate, displayedComponents: .date)
                    HStack {
                        Text("Total Amount")
                        Spacer()
                        Text("$")
                        TextField("0.00", text: $billedAmount)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                    }
                } header: {
                    Label("Bill Details", systemImage: "calendar")
                }
                
                // Line Items Breakdown
                Section {
                    if lineItems.isEmpty {
                        HStack {
                            Image(systemName: "info.circle")
                                .foregroundColor(.secondary)
                            Text("No line items detected. Tap + to add manually.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        ForEach($lineItems) { $item in
                            if item.kind == .payment {
                                // Payment / credit / adjustment row — shown separately,
                                // excluded from the charges total.
                                HStack(spacing: 10) {
                                    Image(systemName: "arrow.down.left.circle.fill")
                                        .foregroundColor(.green)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.description.isEmpty ? "Payment / Credit" : item.description)
                                            .font(.subheadline)
                                        Text("Payment / Credit")
                                            .font(.caption2).foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Text(item.amount, format: .currency(code: "USD"))
                                        .fontWeight(.medium)
                                        .foregroundColor(item.amount < 0 ? .green : .secondary)
                                }
                            } else {
                                LineItemRow(item: $item)
                            }
                        }
                        .onDelete { offsets in
                            lineItems.remove(atOffsets: offsets)
                        }

                        // Charges subtotal — selected charge rows only (payments excluded)
                        let hasPayments = lineItems.contains { $0.kind == .payment }
                        let chargesTotal = lineItems
                            .filter { $0.kind == .charge && $0.isSelected }
                            .reduce(0) { $0 + $1.amount }
                        HStack {
                            Text(hasPayments ? "Charges Total" : "Line Items Total")
                                .fontWeight(.medium)
                            Spacer()
                            Text(chargesTotal, format: .currency(code: "USD"))
                                .fontWeight(.semibold)
                                .foregroundColor(.accentColor)
                        }

                        // Payments & credits subtotal
                        if hasPayments {
                            let paymentsTotal = lineItems
                                .filter { $0.kind == .payment }
                                .reduce(0) { $0 + $1.amount }
                            HStack {
                                Text("Payments & Credits")
                                    .fontWeight(.medium)
                                Spacer()
                                Text(paymentsTotal, format: .currency(code: "USD"))
                                    .fontWeight(.semibold)
                                    .foregroundColor(.green)
                            }
                        }
                    }
                } header: {
                    let matchedCount = lineItems.filter { $0.matchedMedicalCode != nil }.count
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Label("Line Items (\(lineItems.count))", systemImage: "list.bullet.rectangle")
                                .foregroundColor(.orange)
                            if matchedCount > 0 {
                                Text("\(matchedCount) matched in code database")
                                    .font(.caption2)
                                    .foregroundColor(Color("BrandCyan"))
                            }
                        }
                        Spacer()
                        Button {
                            showingCodeScanner = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "qrcode.viewfinder")
                                Text("Scan Codes")
                            }
                            .font(.caption)
                            .foregroundColor(Color("BrandCyan"))
                        }
                        Button {
                            lineItems.append(ParsedLineItem(code: "", description: "", amount: 0))
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(.accentColor)
                        }
                    }
                }
                
                // Financial Summary
                if !totalCharges.isEmpty || !insuranceAdjustment.isEmpty || !insurancePaid.isEmpty || !amountDue.isEmpty {
                    Section {
                        if !totalCharges.isEmpty {
                            HStack(spacing: 10) {
                                Image(systemName: "dollarsign.circle.fill").foregroundColor(Color("BrandCyan")).frame(width: 20)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Total Charges").font(.caption).foregroundColor(.secondary)
                                    Text("$\(totalCharges)").font(.subheadline).fontWeight(.semibold)
                                }
                            }
                        }
                        if !insuranceAdjustment.isEmpty {
                            HStack(spacing: 10) {
                                Image(systemName: "arrow.down.circle.fill").foregroundColor(.orange).frame(width: 20)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Insurance Adj.").font(.caption).foregroundColor(.secondary)
                                    Text("-$\(insuranceAdjustment)").font(.subheadline).fontWeight(.semibold)
                                }
                            }
                        }
                        if !insurancePaid.isEmpty {
                            HStack(spacing: 10) {
                                Image(systemName: "checkmark.circle.fill").foregroundColor(.green).frame(width: 20)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Insurance Paid").font(.caption).foregroundColor(.secondary)
                                    Text("-$\(insurancePaid)").font(.subheadline).fontWeight(.semibold)
                                }
                            }
                        }
                        if !amountDue.isEmpty {
                            HStack(spacing: 10) {
                                Image(systemName: "exclamationmark.circle.fill").foregroundColor(.red).frame(width: 20)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Amount Due").font(.caption).foregroundColor(.secondary)
                                    Text("$\(amountDue)").font(.subheadline).fontWeight(.semibold).foregroundColor(.red)
                                }
                            }
                        }
                    } header: {
                        Label("Financial Summary", systemImage: "dollarsign.circle.fill")
                            .foregroundColor(Color("BrandCyan"))
                    }
                }
                
                // Scanned Totals
                if !lineItems.isEmpty {
                    Section("Scanned Totals") {
                        let charges = lineItems.filter { $0.kind == .charge }
                        let allTotal = charges.reduce(0) { $0 + $1.amount }
                        let selectedTotal = charges.filter(\.isSelected).reduce(0) { $0 + $1.amount }
                        HStack {
                            Text("All Codes Total")
                            Spacer()
                            Text(allTotal, format: .currency(code: "USD"))
                                .foregroundColor(.secondary)
                        }
                        if lineItems.contains(where: { !$0.isSelected }) {
                            HStack {
                                Text("Selected Total").fontWeight(.medium)
                                Spacer()
                                Text(selectedTotal, format: .currency(code: "USD"))
                                    .fontWeight(.semibold)
                                    .foregroundColor(.accentColor)
                            }
                        }
                    }
                }
                
                // Database Price Comparison
                if lineItems.contains(where: { $0.matchedMedicalCode?.hasValidPricing == true }) {
                    Section("Database Price Comparison") {
                        ForEach(lineItems.filter { $0.matchedMedicalCode?.hasValidPricing == true }) { item in
                            if let mc = item.matchedMedicalCode {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.code)
                                            .font(.system(.caption, design: .monospaced))
                                            .fontWeight(.semibold)
                                        Text(mc.formattedPriceRange)
                                            .font(.caption2)
                                            .foregroundColor(.green)
                                    }
                                    Spacer()
                                    if item.amount > 0 {
                                        let avg = mc.priceAverage ?? 0
                                        let diff = item.amount - avg
                                        VStack(alignment: .trailing, spacing: 2) {
                                            Text("Billed: \(item.amount, format: .currency(code: "USD"))")
                                                .font(.caption)
                                            if avg > 0 {
                                                Text(diff > 0 ? "+\(diff, format: .currency(code: "USD"))" : "\(diff, format: .currency(code: "USD"))")
                                                    .font(.caption2)
                                                    .foregroundColor(diff > 50 ? .red : diff < -50 ? .green : .secondary)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                
                // Raw text (collapsible for debugging)
                Section {
                    DisclosureGroup("Raw OCR Text") {
                        VStack(alignment: .leading, spacing: 8) {
                            if !patientText.isEmpty {
                                Text("Patient:").font(.caption).fontWeight(.bold)
                                Text(patientText).font(.caption2).foregroundColor(.secondary)
                            }
                            if !providerText.isEmpty {
                                Text("Provider:").font(.caption).fontWeight(.bold)
                                Text(providerText).font(.caption2).foregroundColor(.secondary)
                            }
                            if !insuranceText.isEmpty {
                                Text("Insurance:").font(.caption).fontWeight(.bold)
                                Text(insuranceText).font(.caption2).foregroundColor(.secondary)
                            }
                            if !procedureText.isEmpty {
                                Text("Procedures:").font(.caption).fontWeight(.bold)
                                Text(procedureText).font(.caption2).foregroundColor(.secondary)
                            }

                            Button {
                                let dump = """
                                === PATIENT ===
                                \(patientText)
                                === PROVIDER ===
                                \(providerText)
                                === INSURANCE ===
                                \(insuranceText)
                                === PROCEDURES ===
                                \(procedureText)
                                """
                                UIPasteboard.general.string = dump
                                rawOCRCopied = true
                            } label: {
                                Label(rawOCRCopied ? "Copied!" : "Copy All OCR Text",
                                      systemImage: rawOCRCopied ? "checkmark.circle.fill" : "doc.on.doc")
                                    .font(.caption)
                            }
                            .padding(.top, 4)
                        }
                    }
                }
            }
            .navigationTitle("Review Bill")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        saveBill()
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Save")
                        }
                    }
                    .disabled(isSaving)
                }
            }
            .onAppear { parseAllRegions() }
            .alert("Existing Bill Found", isPresented: $showingDuplicateAlert) {
                Button("Replace Existing", role: .destructive) {
                    replaceExistingClaim()
                }
                Button("Keep Both") {
                    saveAsNewClaim()
                }
                Button("Cancel", role: .cancel) {
                    pendingClaim = nil
                    pendingProviderId = nil
                    isSaving = false
                }
            } message: {
                if let dup = duplicateClaim {
                    let dateStr = dup.serviceDate.formatted(date: .abbreviated, time: .omitted)
                    let amtStr = String(format: "$%.2f", dup.billedAmount)
                    Text("A bill from \(dup.providerName ?? "this provider") dated \(dateStr) for \(amtStr) already exists.\n\nReplace it with this scan, or keep both?")
                } else {
                    Text("A similar bill already exists.")
                }
            }
            .alert("Different Patient", isPresented: $showingPatientPrompt) {
                Button("Create \"\(scannedFirstName) \(scannedLastName)\"") {
                    createPatientFromScanAndSave()
                }
                if let matched = matchedExistingPatient {
                    Button("Use \"\(matched.displayName)\"") {
                        resolvedPatientId = matched.id
                        appState.selectPatient(matched.id)
                        continueSaveBill()
                    }
                }
                if let currentId = appState.selectedPatientId,
                   let current = patientDataService.patients.first(where: { $0.id == currentId }) {
                    Button("Use Current (\(current.displayName))") {
                        resolvedPatientId = currentId
                        continueSaveBill()
                    }
                }
                Button("Cancel", role: .cancel) {
                    isSaving = false
                }
            } message: {
                let currentName = patientDataService.patients.first(where: { $0.id == appState.selectedPatientId })?.displayName ?? "selected patient"
                Text("This bill is for \"\(patientName)\" but the current patient is \"\(currentName)\".\n\nWho should this bill be saved for?")
            }
            .alert("No Patient", isPresented: $showingNoPatientAlert) {
                if !patientName.isEmpty {
                    Button("Create \"\(scannedFirstName) \(scannedLastName)\"") {
                        createPatientFromScanAndSave()
                    }
                }
                Button("Cancel", role: .cancel) {
                    isSaving = false
                }
            } message: {
                if !patientName.isEmpty {
                    Text("No patient is selected. Create a patient from the scanned name \"\(patientName)\"?")
                } else {
                    Text("No patient is selected. Please go to the Patients tab and add a patient first.")
                }
            }
            .sheet(isPresented: $showingCodeScanner) {
                ScannerView(onImportCodes: { scannedCodes in
                    importScannedCodes(scannedCodes)
                })
                .environmentObject(appState)
            }
        }
    }
    
    @ViewBuilder
    private func fieldRow(_ label: String, _ value: Binding<String>, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(.accentColor)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.caption).foregroundColor(.secondary)
                TextField(label, text: value).font(.subheadline)
            }
        }
    }
    
    // MARK: - Parse All Regions
    
    private func parseAllRegions() {
        #if DEBUG
        print("── BillReview: Patient OCR ──\n\(patientText)")
        print("── BillReview: Provider OCR ──\n\(providerText)")
        print("── BillReview: Insurance OCR ──\n\(insuranceText)")
        print("── BillReview: Procedure OCR ──\n\(procedureText)")
        #endif
        
        parsePatientFields()
        parseProviderFields()
        parseInsuranceFields()

        // Detect provider template after provider name is known.
        // Inline lookup so BillScannerView doesn't require ProviderTemplateManager
        // to be in the same compilation unit.
        detectedTemplate = BillReviewView.findTemplate(for: providerName)
        #if DEBUG
        if let t = detectedTemplate {
            print("── Template matched: \(t.displayName) (\(t.billFormat.rawValue))")
        }
        #endif

        // Remember this provider's box layout for next time (auto-applied on
        // future scans via ScanLayoutStore.lastUsedLayout / the Layouts menu).
        if var layout = usedLayout, !providerName.isEmpty {
            layout.displayName = providerName
            ScanLayoutStore.save(layout, for: providerName)
            #if DEBUG
            print("── Saved scan layout for provider: \(providerName)")
            #endif
        }

        parseLineItems()
        lookupLineItemCodes()
        
        #if DEBUG
        print("── BillReview: Parsed \(lineItems.count) line items ──")
        for item in lineItems {
            print("  [\(item.code)] \(item.description) → $\(String(format: "%.2f", item.amount))")
        }
        print("  Patient: \(patientName), Account: \(accountNumber), MRN: \(mrn), Admit: \(admitDate), Discharge: \(dischargeDate)")
        print("  Provider: \(providerName), Phone: \(providerPhone), Fax: \(providerFax), Email: \(providerEmail), NPI: \(providerNPI)")
        print("  Insurance: \(insuranceCarrier), Policy: \(policyNumber), Member: \(memberId), Discharge: \(dischargeDate)")
        #endif
        
        // Compute total from line items if not already set (charges only)
        if billedAmount.isEmpty && !lineItems.isEmpty {
            let total = lineItems.filter { $0.kind == .charge }.reduce(0) { $0 + $1.amount }
            billedAmount = String(format: "%.2f", total)
        }
    }
    
    // MARK: - Patient Parsing
    
    private func parsePatientFields() {
        let rawLines = patientText.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        
        // ── Filter postal/barcode artifacts ──
        let lines = rawLines.filter { line in
            let upper = line.uppercased()
            // Postal barcodes: start with > or contain long digit sequences like "TU25 1003 59569"
            if line.hasPrefix(">") { return false }
            if upper.contains("ADDRESS SERVICE") || upper.contains("ADDRESSEE") { return false }
            if upper.contains("RETURN SERVICE") || upper.contains("PRESORT") { return false }
            // Lines that are mostly digits with spaces (postal routing codes)
            let digitRatio = Double(line.filter { $0.isNumber }.count) / Double(max(line.count, 1))
            if digitRatio > 0.6 && line.count > 10 { return false }
            // Lines starting with barcode chars
            if line.hasPrefix("|") || line.hasPrefix("!") { return false }
            return true
        }
        
        let pairs = extractAllLabelValuePairs(from: lines)
        
        for (label, value) in pairs {
            let key = label.lowercased()
            if (key.contains("patient") || key.contains("name") || key.contains("insured") || key.contains("subscriber"))
                && !key.contains("address") && !key.contains("balance") && !key.contains("amount") {
                if patientName.isEmpty && looksLikeName(value) { patientName = value }
            } else if key.contains("account") || key.contains("acct") || key.contains("voucher") {
                if accountNumber.isEmpty { accountNumber = value }
            } else if key.contains("birth") || key == "dob" {
                if dateOfBirth.isEmpty { dateOfBirth = value }
            } else if key.contains("date of service") || key.contains("service date") || key == "dos" {
                if let date = parseDate(value) { serviceDate = date }
            } else if key.contains("address") {
                if patientAddress.isEmpty { patientAddress = value }
            } else if key == "mrn" || key.contains("medical record") {
                if mrn.isEmpty { mrn = value }
            } else if key.contains("discharge") {
                if dischargeDate.isEmpty { dischargeDate = value }
            }
        }
        
        // Fallback: two-line OCR pattern — label on one line, value on the next
        // e.g. "Date of Service:" / "11/10/2024"  or  "Patient:" / "John Smith"
        let datePattern = #"\d{1,2}[/-]\d{1,2}[/-]\d{2,4}"#
        for (i, line) in lines.enumerated() {
            guard i + 1 < lines.count else { break }
            let lower = line.lowercased().trimmingCharacters(in: .whitespaces)
            let next  = lines[i + 1].trimmingCharacters(in: .whitespaces)
            if (lower.hasPrefix("patient") || lower.hasPrefix("name")) && lower.hasSuffix(":")
                && patientName.isEmpty && looksLikeName(next) {
                patientName = next
            } else if (lower.contains("date of service") || lower.contains("service date") || lower == "dos:")
                && serviceDate == Date()
                && next.range(of: datePattern, options: .regularExpression) != nil {
                if let d = parseDate(next) { serviceDate = d }
            } else if lower.contains("account") && lower.hasSuffix(":")
                && accountNumber.isEmpty && !next.contains(":") {
                accountNumber = next
            } else if (lower == "mrn:" || lower == "medical record:") && mrn.isEmpty {
                mrn = next
            } else if lower.contains("admit") && lower.hasSuffix(":") && admitDate.isEmpty
                && next.range(of: datePattern, options: .regularExpression) != nil {
                admitDate = next
            } else if lower.contains("discharge") && lower.hasSuffix(":") && dischargeDate.isEmpty
                && next.range(of: datePattern, options: .regularExpression) != nil {
                dischargeDate = next
            }
        }

        // Fallback: find first name-like line (skip provider-looking headers)
        if patientName.isEmpty {
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.contains(":") { continue }
                // Skip lines that look like provider/facility headers
                let upper = trimmed.uppercased()
                if upper.contains("MEDICAL") || upper.contains("HOSPITAL") || upper.contains("CLINIC")
                    || upper.contains("HEALTH") || upper.contains("ASSOCIATES") || upper.contains("ASSOC") { continue }
                // Skip address lines
                if looksLikeAddress(trimmed) { continue }
                if looksLikeName(trimmed) {
                    patientName = trimmed; break
                }
            }
        }

        // Fallback 2: a name merged onto an address line, e.g.
        // "PO BOX 391402  MARY M ARSENAULT" — extract the longest run of
        // consecutive name-like words (skipping address/provider tokens).
        if patientName.isEmpty {
            let stop: Set<String> = ["PO", "BOX", "STREET", "ST", "AVE", "AVENUE",
                "ROAD", "RD", "SUITE", "STE", "DR", "LANE", "LN", "APT", "UNIT",
                "FL", "DELAND", "DELTONA", "MEDICAL", "HOSPITAL", "CLINIC", "ASSOC",
                "ASSOCIATES", "ADDRESSEE", "ADDRESS", "SERVICE", "REQUESTED",
                "STATEMENT", "PATIENT", "ACCOUNT", "VOUCHER"]
            for line in lines {
                var run: [String] = [], best: [String] = []
                for w in line.split(separator: " ").map(String.init) {
                    let isNameWord = (w.first?.isLetter == true)
                        && w.allSatisfy { $0.isLetter || $0 == "." || $0 == "'" || $0 == "-" }
                    if isNameWord, !stop.contains(w.uppercased()) {
                        run.append(w)
                        if run.count > best.count { best = run }
                    } else { run = [] }
                }
                if best.count >= 2 && best.count <= 4 {
                    patientName = best.joined(separator: " "); break
                }
            }
        }

        // Fallback: find address after patient name
        if patientAddress.isEmpty {
            var foundName = false
            for line in lines {
                if !patientName.isEmpty && line.uppercased().contains(patientName.uppercased()) {
                    foundName = true; continue
                }
                if foundName && looksLikeAddress(line) {
                    patientAddress = line
                    // Check if next line is city/state/ZIP continuation
                    if let idx = lines.firstIndex(of: line), idx + 1 < lines.count {
                        let next = lines[idx + 1]
                        if next.range(of: #"\b\d{5}(-\d{4})?\b"#, options: .regularExpression) != nil {
                            patientAddress += ", " + next
                        }
                    }
                    break
                }
            }
            // Broader fallback: any address-looking line
            if patientAddress.isEmpty {
                for line in lines {
                    if looksLikeAddress(line) {
                        patientAddress = line
                        if let idx = lines.firstIndex(of: line), idx + 1 < lines.count {
                            let next = lines[idx + 1]
                            if next.range(of: #"\b\d{5}(-\d{4})?\b"#, options: .regularExpression) != nil {
                                patientAddress += ", " + next
                            }
                        }
                        break
                    }
                }
            }
        }
    }
    
    // MARK: - Provider Parsing
    
    private func parseProviderFields() {
        // ── Credit-card / "pay by card" billing-box stripping ────────────────
        // A bill's provider region frequently sits next to a "IF PAYING BY
        // MASTERCARD…" box. OCR row-grouping merges the two (provider header on the
        // left, billing box on the right) into single lines. Strip the billing box
        // UP FRONT so NO downstream field — name, address, phone — can pick up its
        // text (CARDHOLDER NAME, EXP. DATE, etc.).
        let creditCardTerms: Set<String> = [
            "cardholder", "card holder", "card number", "cardnumber",
            "exp date", "exp. date", "expiration", "expiry",
            "verification", "cvv", "cvc", "security code",
            "signature", "mastercard", "visa", "amex",
            "american express", "discover", "credit card"
        ]
        func isCreditCardLine(_ line: String) -> Bool {
            let lower = line.lowercased()
            return creditCardTerms.contains(where: { lower.contains($0) })
        }

        // Markers that begin the billing box. Matched at word boundaries so e.g.
        // "VISA" doesn't clip "VISALIA" and "AMEX" doesn't clip a real word.
        let billingBoxMarkers = ["IF PAYING", "FILL OUT", "CHECK CARD", "USING FOR PAYMENT",
                                 "MASTERCARD", "VISA", "AMEX", "DISCOVER", "CARD NUMBER",
                                 "CARDHOLDER", "VERIFICATION", "EXP DATE", "EXP. DATE",
                                 "EXPIRATION", "SIGNATURE", "CVV", "CREDIT CARD",
                                 "RETURN THIS PORTION", "SHOW AMOUNT", "PAID HERE"]
        func strippedOfBillingBox(_ line: String) -> String {
            let upper = line.uppercased()
            let chars = Array(upper)
            var cut = chars.count
            for marker in billingBoxMarkers {
                guard let r = upper.range(of: marker) else { continue }
                let start = upper.distance(from: upper.startIndex, to: r.lowerBound)
                let end   = upper.distance(from: upper.startIndex, to: r.upperBound)
                let beforeOK = start == 0 || !chars[start - 1].isLetter
                let afterOK  = end >= chars.count || !chars[end].isLetter
                if beforeOK && afterOK && start < cut { cut = start }
            }
            guard cut < chars.count else { return line }
            let idx = line.index(line.startIndex, offsetBy: cut)
            return String(line[line.startIndex..<idx]).trimmingCharacters(in: .whitespaces)
        }

        // Fuzzy backstop for OCR-garbled billing labels the exact markers miss
        // (e.g. "SIGNATURE" → "SIONATURE", "AMOUNT" surviving alone). Drop any line
        // containing a word that's a near-match (edit-distance-tolerant) to a
        // distinctive billing-box field label. These never appear in a real
        // provider letterhead, so this can't discard a genuine name/address.
        let strongBillingWords = ["CARDHOLDER", "SIGNATURE", "VERIFICATION",
                                  "MASTERCARD", "EXPIRATION", "AMOUNT"]
        func isBillingNoise(_ line: String) -> Bool {
            let words = line.uppercased().split { !$0.isLetter }
                .map(String.init).filter { $0.count >= 4 }
            return words.contains { w in
                strongBillingWords.contains { descriptionSimilarity(w, $0) >= 0.82 }
            }
        }

        // Cleaned line set used by EVERY step below: billing box stripped per line,
        // then empties / pure-billing / billing-noise lines dropped.
        let lines = providerText.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .map { strippedOfBillingBox($0) }
            .filter { !$0.isEmpty && !isCreditCardLine($0) && !isBillingNoise($0) }
        let pairs = extractAllLabelValuePairs(from: lines)

        // Medical facility keywords — if a line contains any of these, it's likely a provider name
        let facilityKeywords = ["MEDICAL CENTER", "HOSPITAL", "HEALTH SYSTEM", "HEALTH CENTER",
                                "REGIONAL MEDICAL", "CLINIC", "SURGICAL CENTER", "URGENT CARE",
                                "MEMORIAL", "COMMUNITY HEALTH", "MEDICAL GROUP", "PHYSICIANS",
                                "HEALTHCARE", "AMBULATORY", "IMAGING CENTER", "RADIOLOGY",
                                "LABORATORY", "PATHOLOGY", "ORTHOPAEDIC", "ORTHOPEDIC",
                                // Extended — family/general practices & wellness centers
                                "FAMILY MEDICINE", "INTERNAL MEDICINE", "MEDICINE & WELLNESS",
                                "FAMILY PRACTICE", "FAMILY HEALTH", "MEDICAL ASSOC",
                                "WELLNESS CENTER", "WELLNESS CLINIC", "HEALTH & WELLNESS",
                                "MEDICAL PRACTICE", "MEDICAL SERVICES", "HEALTH SERVICES",
                                "CARE CENTER", "CARE CLINIC", "WOMEN'S HEALTH", "WOMEN'S CARE",
                                "PEDIATRICS", "DERMATOLOGY", "CARDIOLOGY", "NEUROLOGY",
                                "ONCOLOGY", "UROLOGY", "GASTROENTEROLOGY", "PULMONOLOGY",
                                "ENDOCRINOLOGY", "RHEUMATOLOGY", "NEPHROLOGY", "HEMATOLOGY"]

        // (billing box already stripped above — `lines`/`pairs` are clean)
        let filteredLines = lines
        let filteredPairs = pairs

        // ── Step 1: Extract labeled fields (credit-card fields excluded) ──
        for (label, value) in filteredPairs {
            let key = label.lowercased()
            if key.contains("provider") || key.contains("facility") || key.contains("hospital") || key.contains("clinic") {
                if providerName.isEmpty { providerName = value }
            } else if key.contains("remit") || key.contains("pay to") || key.contains("send to") || key.contains("return to") || key.contains("bill to") {
                if providerName.isEmpty && looksLikeName(value) { providerName = value }
            } else if key.contains("fax") {
                if providerFax.isEmpty { providerFax = value }
            } else if key.contains("phone") || key.contains("tel") || key.contains("office phone") {
                if providerPhone.isEmpty { providerPhone = value }
            } else if key.contains("email") || key.contains("e-mail") {
                if providerEmail.isEmpty { providerEmail = value }
            } else if key.contains("web") || key.contains("url") || key.contains("site") {
                if providerWebsite.isEmpty { providerWebsite = value }
            } else if key.contains("npi") {
                if providerNPI.isEmpty { providerNPI = value }
            } else if key.contains("tax") || key.contains("ein") || (key.contains("fed") && key.contains("id")) {
                if providerTaxId.isEmpty { providerTaxId = value }
            } else if key.contains("license") || key.contains("lic") {
                if providerLicense.isEmpty { providerLicense = value }
            } else if key.contains("address") && !key.contains("account") {
                if providerAddress.isEmpty { providerAddress = value }
            }
        }
        
        // ── Step 2: Detect facility name by medical keywords (using filtered lines) ──
        if providerName.isEmpty {
            for line in filteredLines {
                let upper = line.uppercased()
                if looksLikeFilename(line) || looksLikeProcedureRow(line) { continue }   // skip filename/window chrome & charges rows
                if facilityKeywords.contains(where: { upper.contains($0) }) {
                    var name = line
                    // Strip statement/department labels that may be on the same line
                    let stripPatterns = ["EMERGENCY DEPT STATEMENT", "INPATIENT STATEMENT",
                                         "OUTPATIENT STATEMENT", "PATIENT STATEMENT",
                                         "BILLING STATEMENT", "EMERGENCY DEPARTMENT"]
                    for pattern in stripPatterns {
                        if let range = name.uppercased().range(of: pattern) {
                            let startIdx = name.index(name.startIndex, offsetBy: name.distance(from: name.startIndex, to: range.lowerBound))
                            name = String(name[name.startIndex..<startIdx]).trimmingCharacters(in: .whitespaces)
                        }
                    }
                    // Strip a LEADING street-address segment when OCR merged
                    // "1070 NORTH STONE STREET SUITE  WEST VOLUSIA MEDICAL ASSOCIAT"
                    // (street first, name after). Requires a leading street number so
                    // it can't eat a normal facility name.
                    let streetSuffix = #"(STREET|ST|AVENUE|AVE|ROAD|RD|BLVD|DRIVE|DR|LANE|LN|SUITE|STE|WAY|COURT|CT|PLACE|PL|HWY|HIGHWAY|PIKE|CIRCLE|CIR|BOX)"#
                    if let r = name.range(of: "^\\s*\\d{1,6}\\s+.*\\b\(streetSuffix)\\b\\.?\\s+",
                                          options: [.regularExpression, .caseInsensitive]) {
                        let stripped = String(name[r.upperBound...]).trimmingCharacters(in: .whitespaces)
                        if !stripped.isEmpty,
                           facilityKeywords.contains(where: { stripped.uppercased().contains($0) }) {
                            name = stripped
                        }
                    }
                    // Strip a TRAILING street-address segment (name then street)
                    if let addrRange = name.range(of: #"\s+\d{2,5}\s+[A-Za-z]"#, options: .regularExpression) {
                        let afterAddr = String(name[addrRange.lowerBound...])
                        if looksLikeAddress(afterAddr) {
                            name = String(name[name.startIndex..<addrRange.lowerBound]).trimmingCharacters(in: .whitespaces)
                        }
                    }
                    name = name.trimmingCharacters(in: .whitespaces)
                    // No looksLikeAddress guard here: this line CONTAINS a facility
                    // keyword, so it IS the provider name — even if it contains a
                    // directional word like "WEST"/"NORTH" that looksLikeAddress flags.
                    if !name.isEmpty {
                        providerName = name
                        break
                    }
                }
            }
        }
        
        // ── Step 3: Parse combined Phone/Fax lines ──
        let phonePattern = #"\(?\d{3}\)?[-.\s]?\d{3}[-.\s]?\d{4}"#
        for line in lines {
            // Split "Phone: (407) 555-0100 | Fax: (407) 555-0101"
            let parts = line.components(separatedBy: "|")
            for part in parts {
                let partLower = part.lowercased().trimmingCharacters(in: .whitespaces)
                if partLower.contains("fax") && providerFax.isEmpty {
                    if let range = part.range(of: phonePattern, options: .regularExpression) {
                        providerFax = String(part[range])
                    }
                } else if (partLower.contains("phone") || partLower.contains("tel")) && providerPhone.isEmpty {
                    if let range = part.range(of: phonePattern, options: .regularExpression) {
                        providerPhone = String(part[range])
                    }
                }
            }
        }
        
        // ── Step 4: REMIT TO address collection ──
        // Collect address lines after a REMIT TO / PAY TO marker.
        // IMPORTANT: address lines (e.g. "1070 N STONE ST") must NOT be used
        // to overwrite providerName. Only set providerName from lines that
        // explicitly look like a facility name AND come BEFORE any address line.
        if providerAddress.isEmpty {
            var foundRemit = false
            var addressParts: [String] = []
            var nameBeforeAddress: String? = nil
            for line in filteredLines {
                if isCreditCardLine(line) { continue }
                let lower = line.lowercased()
                if lower.contains("remit to") || lower.contains("pay to") || lower.contains("send to")
                    || lower.contains("return to") || lower.contains("bill to") {
                    foundRemit = true
                    // Inline value after the marker label
                    if let colonIdx = line.firstIndex(of: ":") {
                        let after = String(line[line.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)
                        if !after.isEmpty && providerName.isEmpty && looksLikeName(after) {
                            nameBeforeAddress = after
                        }
                    }
                    continue
                }
                if foundRemit {
                    let isAddr = looksLikeAddress(line)
                        || line.range(of: #"\b\d{5}(-\d{4})?\b"#, options: .regularExpression) != nil
                    if isAddr {
                        // Commit the name candidate now that we know the next line IS an address
                        if let n = nameBeforeAddress, providerName.isEmpty { providerName = n }
                        nameBeforeAddress = nil
                        addressParts.append(line)
                    } else if addressParts.isEmpty && !looksLikePhone(line) && !line.contains(":") && line.count > 3 {
                        // Candidate name line before any address has been seen
                        if looksLikeName(line) { nameBeforeAddress = line }
                    } else if !addressParts.isEmpty {
                        // Continuation address line or end-of-block
                        if looksLikeAddress(line) || line.range(of: #"\b\d{5}(-\d{4})?\b"#, options: .regularExpression) != nil {
                            addressParts.append(line)
                        } else {
                            break
                        }
                    }
                }
            }
            if !addressParts.isEmpty {
                providerAddress = addressParts.joined(separator: ", ")
            }
        }
        // ── Step 5: Fallback — first non-label, non-phone, non-address line ──
        if providerName.isEmpty {
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                // Strip the billing box first so a name merged onto the same OCR row
                // ("WEST VOLUSIA MEDICAL ASSOCIAT   IF PAYING BY MASTERCARD…") keeps
                // the name rather than being discarded for containing "MASTERCARD".
                var candidateLine = strippedOfBillingBox(trimmed)
                if candidateLine.isEmpty { continue }
                // Strip any trailing document-type label (e.g. "PATIENT STATEMENT")
                // before deciding whether to skip this line, so that a provider name
                // like "ORLANDO FAMILY MEDICINE & WELLNESS    PATIENT STATEMENT" is
                // not discarded just because the label happens to land on the same line.
                let statementLabels = ["PATIENT STATEMENT", "BILLING STATEMENT",
                                       "INPATIENT STATEMENT", "OUTPATIENT STATEMENT",
                                       "EMERGENCY DEPT STATEMENT", "ACCOUNT STATEMENT"]
                for label in statementLabels {
                    if let range = candidateLine.uppercased().range(of: label) {
                        let stripped = String(candidateLine[candidateLine.startIndex..<range.lowerBound])
                            .trimmingCharacters(in: .whitespaces)
                        if !stripped.isEmpty { candidateLine = stripped }
                    }
                }
                let candidateUpper = candidateLine.uppercased()
                // Now apply the original skip guards on the cleaned candidate
                if candidateUpper.contains("STATEMENT") && !facilityKeywords.contains(where: { candidateUpper.contains($0) }) { continue }
                if looksLikeFilename(candidateLine) || looksLikeProcedureRow(candidateLine) { continue }   // skip filename/window chrome & charges rows
                if !candidateLine.contains(":") && candidateLine.count > 3 && !looksLikePhone(candidateLine) && !looksLikeAddress(candidateLine) {
                    providerName = candidateLine; break
                }
            }
        }
        
        // ── Step 5b: Longest-line fallback ──
        // If Steps 1–5 all failed (common with severely garbled dark-bg OCR),
        // pick the longest line that:
        //   • is all-caps or title-case (typical for a facility header)
        //   • is NOT an address or phone number
        //   • is NOT a known statement label
        if providerName.isEmpty {
            let statementWords = ["STATEMENT", "INVOICE", "RECEIPT", "NOTICE", "ACCOUNT"]
            let candidates = lines.filter { line in
                let t = line.trimmingCharacters(in: .whitespaces)
                guard t.count > 5, !t.contains(":"),
                      !looksLikeAddress(t), !looksLikePhone(t),
                      !looksLikeFilename(t), !looksLikeProcedureRow(t) else { return false }
                let upper = t.uppercased()
                if statementWords.contains(where: { upper.contains($0) }) { return false }
                // Must look like a name: mostly letters, spaces, &, ., -
                let nonNameChars = t.filter { !$0.isLetter && !$0.isWhitespace && !"&.-,'".contains($0) }
                return Double(nonNameChars.count) / Double(max(t.count, 1)) < 0.15
            }
            if let best = candidates.max(by: { $0.count < $1.count }) {
                // Apply statement-label strip one more time
                var name = best
                let statementLabels = ["PATIENT STATEMENT", "BILLING STATEMENT",
                                       "INPATIENT STATEMENT", "OUTPATIENT STATEMENT",
                                       "EMERGENCY DEPT STATEMENT", "ACCOUNT STATEMENT"]
                for label in statementLabels {
                    if let r = name.uppercased().range(of: label) {
                        let stripped = String(name[name.startIndex..<r.lowerBound])
                            .trimmingCharacters(in: .whitespaces)
                        if !stripped.isEmpty { name = stripped }
                    }
                }
                if !name.isEmpty { providerName = name }
            }
        }

        // ── Step 6: Collect address by scanning for address-pattern lines ──
        if providerAddress.isEmpty {
            var addressParts: [String] = []
            var collecting = false
            for line in lines {
                // Never treat the facility name as address — looksLikeAddress can
                // be fooled by a directional word ("WEST VOLUSIA…"). The name has a
                // facility keyword; the street address does not.
                if facilityKeywords.contains(where: { line.uppercased().contains($0) })
                    || line.caseInsensitiveCompare(providerName) == .orderedSame {
                    continue
                }
                if looksLikeAddress(line) {
                    addressParts.append(line)
                    collecting = true
                } else if collecting {
                    if line.range(of: #"\b\d{5}(-\d{4})?\b"#, options: .regularExpression) != nil {
                        addressParts.append(line)
                    }
                    break
                }
            }
            if !addressParts.isEmpty {
                providerAddress = addressParts.joined(separator: ", ")
            }
        }
        
        // ── Step 7: Remaining standalone fields ──
        if providerPhone.isEmpty {
            for line in lines {
                if looksLikePhone(line) {
                    if let range = line.range(of: phonePattern, options: .regularExpression) {
                        providerPhone = String(line[range])
                    } else {
                        providerPhone = line
                    }
                    break
                }
            }
        }
        if providerEmail.isEmpty {
            let emailPattern = #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#
            for line in lines {
                if let range = line.range(of: emailPattern, options: .regularExpression) {
                    providerEmail = String(line[range]); break
                }
            }
        }
        if providerWebsite.isEmpty {
            let webPattern = #"(?:https?://|www\.)[A-Za-z0-9._~:/?#\[\]@!$&'()*+,;=-]+"#
            for line in lines {
                if let range = line.range(of: webPattern, options: .regularExpression) {
                    providerWebsite = String(line[range]); break
                }
            }
        }
        if providerFax.isEmpty {
            for line in lines {
                if line.lowercased().contains("fax") {
                    if let range = line.range(of: phonePattern, options: .regularExpression) {
                        providerFax = String(line[range]); break
                    }
                }
            }
        }
        if providerNPI.isEmpty {
            for line in lines {
                if line.lowercased().contains("npi") {
                    if let range = line.range(of: #"\b\d{10}\b"#, options: .regularExpression) {
                        providerNPI = String(line[range]); break
                    }
                }
            }
        }
        if providerTaxId.isEmpty {
            for line in lines {
                let lower = line.lowercased()
                if lower.contains("tax") || lower.contains("ein") || lower.contains("fed") {
                    if let range = line.range(of: #"\b\d{2}-?\d{7}\b"#, options: .regularExpression) {
                        providerTaxId = String(line[range]); break
                    }
                }
            }
        }
        
        // ── Step 8: Cross-scan other regions for provider if still empty ──
        // NOTE: procedureText is deliberately excluded — the charges table contains
        // CPT descriptions ("Initial Hospital Care", "Hospital Discharge Day") that
        // match the "HOSPITAL" facility keyword and would be mistaken for the name.
        if providerName.isEmpty {
            let allTexts = [patientText, insuranceText]
            for regionText in allTexts {
                let regionLines = regionText.components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                for line in regionLines {
                    let upper = line.uppercased()
                    if looksLikeProcedureRow(line) || looksLikeFilename(line) { continue }
                    if facilityKeywords.contains(where: { upper.contains($0) }) {
                        var name = line
                        let stripPatterns = ["EMERGENCY DEPT STATEMENT", "INPATIENT STATEMENT",
                                             "OUTPATIENT STATEMENT", "PATIENT STATEMENT",
                                             "BILLING STATEMENT", "EMERGENCY DEPARTMENT"]
                        for pattern in stripPatterns {
                            if let range = name.uppercased().range(of: pattern) {
                                let startIdx = name.index(name.startIndex, offsetBy: name.distance(from: name.startIndex, to: range.lowerBound))
                                name = String(name[name.startIndex..<startIdx]).trimmingCharacters(in: .whitespaces)
                            }
                        }
                        if !name.isEmpty { providerName = name }
                        break
                    }
                }
                if !providerName.isEmpty { break }
            }
        }

        // ── Step 9: Correct a misread state code in the address (e.g. "FR" → "FL") ──
        if !providerAddress.isEmpty {
            providerAddress = correctStateCode(in: providerAddress)
        }

        #if DEBUG
        print("── Provider parsed: name=\"\(providerName)\" phone=\"\(providerPhone)\" fax=\"\(providerFax)\" addr=\"\(providerAddress)\"")
        #endif
    }
    
    // MARK: - Insurance Parsing
    
    private func parseInsuranceFields() {
        let lines = insuranceText.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let pairs = extractAllLabelValuePairs(from: lines)
        
        for (label, value) in pairs {
            let key = label.lowercased()
            if key.contains("insurance") || key.contains("carrier") || key.contains("payer") || key.contains("plan name") {
                if insuranceCarrier.isEmpty { insuranceCarrier = value }
            } else if key.contains("policy") {
                if policyNumber.isEmpty { policyNumber = value }
            } else if key.contains("member") || key.contains("subscriber id") || (key == "id" && memberId.isEmpty) {
                if memberId.isEmpty { memberId = value }
            } else if key.contains("group") {
                if groupNumber.isEmpty { groupNumber = value }
            } else if key.contains("plan type") || key.contains("type") {
                if insurancePlanType.isEmpty { insurancePlanType = value }
            } else if key == "mrn" || key.contains("medical record") {
                if mrn.isEmpty { mrn = value }
            } else if key.contains("discharge") {
                if dischargeDate.isEmpty { dischargeDate = value }
            } else if key.contains("admit") {
                if admitDate.isEmpty { admitDate = value }
            }
        }
        
        // Also scan patient text for MRN (it often appears there)
        if mrn.isEmpty {
            let patientPairs = extractAllLabelValuePairs(from:
                patientText.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            )
            for (label, value) in patientPairs {
                let key = label.lowercased()
                if key == "mrn" || key.contains("medical record") {
                    mrn = value; break
                }
            }
        }
        
        // Scan all regions for discharge date if not found in insurance
        if dischargeDate.isEmpty {
            let allRegionTexts = [patientText, providerText, procedureText]
            for regionText in allRegionTexts {
                let regionPairs = extractAllLabelValuePairs(from:
                    regionText.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                )
                for (label, value) in regionPairs {
                    let key = label.lowercased()
                    if key.contains("discharge") {
                        dischargeDate = value; break
                    }
                }
                if !dischargeDate.isEmpty { break }
            }
        }
        
        // Detect plan type from any line (HMO, PPO, etc.)
        if insurancePlanType.isEmpty {
            let allText = insuranceText.uppercased()
            let planPatterns = ["HMO", "PPO", "EPO", "POS", "HDHP", "MEDICARE", "MEDICAID", "TRICARE"]
            for p in planPatterns {
                if allText.contains(p) { insurancePlanType = p; break }
            }
        }
        
        // Fallback: first non-label, non-provider, non-credit-card line = carrier name
        if insuranceCarrier.isEmpty {
            let providerFacilityKeywords = [
                "MEDICAL CENTER", "HOSPITAL", "HEALTH SYSTEM", "CLINIC", "SURGICAL",
                "MEDICAL GROUP", "PHYSICIANS", "HEALTHCARE", "ASSOCIATES", "MEDICAL"
            ]
            let ccTerms = ["CARDHOLDER", "CARD NUMBER", "EXP DATE", "EXPIRATION",
                          "MASTERCARD", "VISA", "SIGNATURE", "VERIFICATION"]
            // Statement-structure / header labels that are not a carrier name.
            let statementNoise = ["ACCOUNT", "PATIENT BALANCE", "SHOW AMOUNT", "PAID HERE",
                                  "STATEMENT", "RETURN THIS", "DUE DATE", "STATEMENT DATE",
                                  "REMIT", "OFFICE PHONE", "PAGE ", "BALANCE", "AMOUNT"]
            for line in lines {
                let upper = line.uppercased()
                guard !line.contains(":"), line.count > 3 else { continue }
                guard !providerFacilityKeywords.contains(where: { upper.contains($0) }) else { continue }
                guard !ccTerms.contains(where: { upper.contains($0) }) else { continue }
                guard !statementNoise.contains(where: { upper.contains($0) }) else { continue }
                guard !looksLikeAddress(line), !looksLikePhone(line) else { continue }
                insuranceCarrier = line; break
            }
        }
    }
    
    // MARK: - Template Detection

    /// Built-in templates. More can be added here as new provider formats are encountered.
    private static let builtInTemplates: [ProviderBillTemplate] = [
        {
            var t = ProviderBillTemplate(
                displayName: "West Volusia Medical Associates",
                matchKeywords: ["west volusia", "volusia medical", "volusia medical assoc"]
            )
            t.billFormat = .accountStatement
            var layout = ProcedureColumnLayout()
            layout.chargesColumnKeywords    = ["charges", "debits", "charges & debits"]
            layout.insurancePendingKeywords = ["insurance pending", "ins pending"]
            layout.paymentsColumnKeywords   = ["payments", "credits", "payments & credits"]
            layout.patientAmountKeywords    = ["patient amount", "patient", "pt amount"]
            layout.visitTotalLabels         = ["visit total", "---- visit total", "---visit total"]
            layout.voucherLabels            = ["voucher:", "voucher #"]
            layout.accountingRowKeywords    = [
                "payment", "adjustment", "transfer", "credit card", "self pay",
                "mastercard", "visa", "check", "write off", "write-off",
                "courtesy", "refund", "cigna", "aetna", "humana", "bcbs",
                "blue cross", "united health", "anthem", "collection"
            ]
            t.procedureColumnLayout = layout
            return t
        }()
    ]

    /// Returns the matching provider template for a given provider name.
    /// Checks UserDefaults-persisted templates first, then built-ins.
    static func findTemplate(for providerName: String) -> ProviderBillTemplate? {
        let lower = providerName.lowercased()

        // Check UserDefaults for user-saved templates
        if let data = UserDefaults.standard.data(forKey: "ProviderBillTemplates_v1"),
           let saved = try? JSONDecoder().decode([ProviderBillTemplate].self, from: data) {
            if let match = saved.first(where: { t in
                t.matchKeywords.contains(where: { lower.contains($0.lowercased()) })
            }) { return match }
        }

        // Fall back to built-ins
        return builtInTemplates.first { t in
            t.matchKeywords.contains(where: { lower.contains($0.lowercased()) })
        }
    }

    // MARK: - Line Item Parsing

    /// Detects the multi-column "account statement" layout from its distinctive
    /// headers/rows so the column-aware parser runs even when the provider-name OCR
    /// is too poor to match a template. ≥2 signals required (standard itemized bills
    /// have none of these), so it can't false-positive on a normal bill.
    private func looksLikeAccountStatement(_ text: String) -> Bool {
        let l = text.lowercased()
        var signals = 0
        if l.contains("voucher")            { signals += 1 }
        if l.contains("visit total")        { signals += 1 }
        if l.contains("insurance pending")  { signals += 1 }
        if l.contains("patient amount")     { signals += 1 }
        if l.contains("icpt")               { signals += 1 }
        if l.contains("charges") && (l.contains("credits") || l.contains("debits")) { signals += 1 }
        return signals >= 2
    }

    private func parseLineItems() {
        // Route to template-specific parser when available
        if let layout = detectedTemplate?.procedureColumnLayout,
           detectedTemplate?.billFormat == .accountStatement {
            parseAccountStatementLineItems(layout: layout)
            return
        }

        // Format-based fallback: recognize the account-statement layout from the
        // procedure text itself, even without a provider-template match.
        if looksLikeAccountStatement(procedureText) {
            var layout = ProcedureColumnLayout()
            layout.accountingRowKeywords += [
                "cigna", "aetna", "humana", "bcbs", "blue cross", "united health",
                "unitedhealth", "anthem", "medicare", "medicaid", "tricare",
                "self pay", "master card", "mastercard", "visa", "discover"
            ]
            parseAccountStatementLineItems(layout: layout)
            return
        }

        let lines = procedureText.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        
        var items: [ParsedLineItem] = []
        
        for line in lines {
            let lower = line.lowercased()
            
            // ── Skip header/label lines ──
            if lower.hasPrefix("date") && (lower.contains("code") || lower.contains("description") || lower.contains("cpt")
                || lower.contains("icpt") || lower.contains("reason") || lower.contains("activity")) { continue }
            if lower.hasPrefix("emergency department") || lower.hasPrefix("charges") { continue }
            // Column sub-headers
            if lower.contains("debits") && lower.contains("credits") { continue }
            if lower.contains("pending") && lower.contains("amount") && lower.contains("insurance") { continue }
            
            // ── Skip insurance transaction lines ──
            // These are payment/adjustment records, not procedures
            let insurancePatterns = [
                "payment", "adjustment", "transfer", "refund", "credit card",
                "self pay", "master card", "mastercard", "visa pay", "check pay",
                "write off", "write-off", "collection", "courtesy"
            ]
            if insurancePatterns.contains(where: { lower.contains($0) }) {
                // But capture negative amounts as insurance payments for running totals
                continue
            }
            
            // ── Skip voucher/visit total lines ──
            // BUT keep a row where OCR merged the "Voucher:" header onto an actual
            // procedure line (it still has a 5-digit CPT + charge), e.g.
            // "Voucher:  07/11/11  99214  2607480  Office/outpatient Visit  131.00  0.00"
            let hasCPTCode = line.range(of: #"\b\d{5}\b"#, options: .regularExpression) != nil
            if (lower.hasPrefix("voucher") && !hasCPTCode)
                || lower.contains("visit total") || lower.contains("---- ") { continue }
            // Skip "Patient:" label lines inside procedure area
            if lower.hasPrefix("patient:") { continue }
            
            // ── Extract financial summary from total/summary lines ──
            // IMPORTANT: check for specific financial labels BEFORE a generic "total" check.
            // A broad lower.contains("total") matches procedure descriptions like
            // "Total Knee Arthroplasty" (code 27447) and routes them to the summary parser,
            // silently dropping $22,500 from the line-items total.
            // Only treat a line as a summary line when:
            //  • it starts with the label (not mid-description), OR
            //  • it contains a recognised financial summary keyword pair
            let isFinancialSummaryLine =
                lower.hasPrefix("total charge") || lower.hasPrefix("subtotal") ||
                lower.hasPrefix("insurance adjust") || lower.hasPrefix("insurance paid") ||
                lower.hasPrefix("ins paid") || lower.hasPrefix("amount due") ||
                lower.hasPrefix("balance due") || lower.hasPrefix("you owe") ||
                lower.hasPrefix("patient resp") ||
                lower.contains("total charges") || lower.contains("total charge:") ||
                lower.contains("insurance adjustment") || lower.contains("insurance paid") ||
                lower.contains("amount due") || lower.contains("balance due") ||
                lower.contains("you owe") || lower.contains("patient responsibility") ||
                // Also catch "---- Total Charges" style labels
                (lower.contains("total") && (lower.contains("charge") || lower.contains("balance") || lower.contains("amount")))

            if isFinancialSummaryLine {
                let amt = extractStrictDollarAmount(from: line) ?? extractPlainAmount(from: line)
                if let amt = amt {
                    if lower.contains("total charge") || lower.contains("subtotal") {
                        totalCharges = String(format: "%.2f", amt)
                        if billedAmount.isEmpty { billedAmount = totalCharges }
                    } else if lower.contains("insurance adjust") || lower.contains("contractual") || lower.contains("write off") || lower.contains("write-off") {
                        insuranceAdjustment = String(format: "%.2f", amt)
                    } else if lower.contains("insurance paid") || lower.contains("ins paid") || lower.contains("ins payment") {
                        insurancePaid = String(format: "%.2f", amt)
                    } else if lower.contains("amount due") || lower.contains("balance due") || lower.contains("you owe") || lower.contains("patient resp") {
                        amountDue = String(format: "%.2f", amt)
                    }
                }
                continue
            }
            
            // Extract dollar amount — try "$" first, then plain decimal fallback
            var amount = extractStrictDollarAmount(from: line)
            if amount == nil {
                amount = extractPlainAmount(from: line)
            }
            
            // Skip statement header / contact rows misread as procedures, e.g.
            // "1  10/24/11  11/08/11  (386) 943-7100  38142  52.74"
            // (Page / Statement Date / Due Date / Phone / Account # / Balance).
            let phonePattern = #"\(?\d{3}\)?[-.\s]?\d{3}[-.\s]\d{4}"#
            if line.range(of: phonePattern, options: .regularExpression) != nil
                || lower.contains("account #") || lower.contains("account number")
                || lower.contains("patient balance") || lower.contains("statement date")
                || lower.contains("due date") || lower.contains("office phone") {
                continue
            }

            // Extract procedure code from the line
            let code = extractProcedureCode(from: line)

            // Must have at least an amount or a code to be a valid line item
            guard amount != nil || code != nil else { continue }
            
            // Build description by stripping code, amount, and date from line
            var desc = line
            
            // Remove the code
            if let code = code, let range = desc.range(of: code) {
                desc = String(desc[range.upperBound...])
            }
            
            // Remove dollar amounts (with $ sign)
            let dollarPattern = #"-?\$[\d,]+\.?\d{0,2}"#
            if let regex = try? NSRegularExpression(pattern: dollarPattern) {
                desc = regex.stringByReplacingMatches(in: desc, range: NSRange(desc.startIndex..., in: desc), withTemplate: "")
            }
            
            // Remove plain negative amounts like -51.55 (insurance payments in same row)
            let negAmtPattern = #"-\d+\.\d{2}"#
            if let regex = try? NSRegularExpression(pattern: negAmtPattern) {
                desc = regex.stringByReplacingMatches(in: desc, range: NSRange(desc.startIndex..., in: desc), withTemplate: "")
            }
            
            // Remove plain 0.00 amounts
            let zeroPattern = #"\b0\.00\b"#
            if let regex = try? NSRegularExpression(pattern: zeroPattern) {
                desc = regex.stringByReplacingMatches(in: desc, range: NSRange(desc.startIndex..., in: desc), withTemplate: "")
            }
            
            // Remove dates (MM/DD/YY or MM/DD/YYYY or MMDDYYYY)
            let datePattern = #"\d{1,2}/\d{1,2}/\d{2,4}"#
            if let regex = try? NSRegularExpression(pattern: datePattern) {
                desc = regex.stringByReplacingMatches(in: desc, range: NSRange(desc.startIndex..., in: desc), withTemplate: "")
            }
            let datePattern2 = #"\b\d{8}\b"#  // 07132011 format dates
            if let regex = try? NSRegularExpression(pattern: datePattern2) {
                desc = regex.stringByReplacingMatches(in: desc, range: NSRange(desc.startIndex..., in: desc), withTemplate: "")
            }

            // Remove standalone 6+ digit voucher / account numbers (e.g. 2607480)
            let longNumPattern = #"\b\d{6,}\b"#
            if let regex = try? NSRegularExpression(pattern: longNumPattern) {
                desc = regex.stringByReplacingMatches(in: desc, range: NSRange(desc.startIndex..., in: desc), withTemplate: "")
            }

            // Remove standalone single digits (quantity column)
            let qtyPattern = #"\b[1-9]\b"#
            if let regex = try? NSRegularExpression(pattern: qtyPattern) {
                desc = regex.stringByReplacingMatches(in: desc, range: NSRange(desc.startIndex..., in: desc), withTemplate: "")
            }
            
            desc = desc.trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "- ,"))
                .trimmingCharacters(in: .whitespaces)
            
            // Skip if we only got a code with no amount (likely a header fragment)
            if amount == nil && desc.isEmpty { continue }

            let newCode = code ?? ""
            // Dedup: the same code + amount appearing twice is an OCR/accumulation
            // artifact (e.g. the table captured twice), not two real charges.
            if !newCode.isEmpty,
               items.contains(where: { $0.code == newCode && abs($0.amount - (amount ?? 0)) < 0.01 }) {
                continue
            }

            items.append(ParsedLineItem(
                code: newCode,
                description: desc.isEmpty ? (code != nil ? "Procedure \(code!)" : "Unknown") : desc,
                amount: amount ?? 0
            ))
        }

        lineItems = items
    }
    
    // MARK: - Code Classification & Database Lookup
    
    /// Classify a code string into its medical code type using ScannerViewModel patterns
    private func classifyCodeType(_ code: String) -> MedicalCodeType? {
        let upper = code.uppercased()
        guard !upper.isEmpty else { return nil }
        
        let first = upper.first!
        
        // HCPCS: letter A-V + 4 digits
        if first.isLetter && first >= "A" && first <= "V" && upper.count == 5 {
            let digits = upper.dropFirst()
            if digits.allSatisfy(\.isNumber) { return .hcpcs }
        }
        
        // ICD-10-CM: letter + 2 digits + optional dot + 1-4 alphanumeric
        if first.isLetter && first != "U" && upper.count >= 3 {
            let afterFirst = upper.dropFirst()
            if afterFirst.prefix(2).allSatisfy(\.isNumber) {
                if upper.contains(".") || upper.count <= 7 {
                    return .icd10
                }
            }
        }
        
        // ICD-10-PCS: 7 alphanumeric
        if upper.count == 7 && upper.allSatisfy({ $0.isNumber || $0.isLetter }) {
            return .icd10pcs
        }
        
        // CPT: 5 digits in valid range
        if upper.count == 5 && upper.allSatisfy(\.isNumber) {
            if let num = Int(upper), num >= 10000 && num <= 99499 {
                return .cpt
            }
        }
        
        return nil
    }

    // MARK: - OCR Correction Helpers

    /// Common OCR character confusions for billing codes (digits + look-alike letters).
    private static let ocrCodeConfusions: [Character: [Character]] = [
        "0": ["O", "8", "6", "9", "D"], "1": ["7", "I", "L"], "2": ["7", "Z"],
        "3": ["8", "9"], "4": ["9"], "5": ["6", "8", "S"], "6": ["5", "8", "0", "G"],
        "7": ["1", "2"], "8": ["9", "0", "6", "3", "B", "5"], "9": ["8", "4", "0", "3"],
        "O": ["0"], "I": ["1"], "L": ["1"], "S": ["5"], "B": ["8"], "Z": ["2"], "G": ["6"]
    ]

    /// Generates candidate code spellings by applying one OCR-confusion swap at each
    /// position — used to recover a misread code (e.g. "98223" → "99223").
    private func ocrCodeVariants(_ code: String) -> [String] {
        let chars = Array(code.uppercased())
        var out: [String] = []
        for i in chars.indices {
            guard let subs = Self.ocrCodeConfusions[chars[i]] else { continue }
            for s in subs {
                var v = chars; v[i] = s; out.append(String(v))
            }
        }
        var seen = Set<String>([code.uppercased()])
        return out.filter { seen.insert($0).inserted }
    }

    /// Looks up a code in the database, trying OCR-confusion variants if the direct
    /// match fails. Returns the (possibly corrected) code and the matched record.
    private func databaseMatch(forCode code: String, ocrDescription: String,
                               using cloudKit: CloudKitService) -> (code: String, match: MedicalCode)? {
        let upper = code.uppercased()
        if let direct = cloudKit.lookupCode(upper) { return (upper, direct) }

        // The code as read wasn't in the database. Try OCR-confusion variants — but ONLY
        // accept one whose canonical description CORROBORATES the OCR text. Otherwise a
        // correctly-read code that is merely missing from the (incomplete) database gets
        // morphed into a different, similar-looking code that happens to be present
        // (e.g. 99233 "Subsequent Hospital Care" → 99283 "Emergency dept visit"). Only a
        // genuine misread like 98223 → 99223 has a matching description, so gate on that.
        let desc = ocrDescription.trimmingCharacters(in: .whitespaces)
        guard !desc.isEmpty else { return nil }
        for variant in ocrCodeVariants(upper) {
            guard variant.count == upper.count, classifyCodeType(variant) != nil,
                  let m = cloudKit.lookupCode(variant) else { continue }
            if descriptionSimilarity(desc, m.shortDescription) >= 0.78 {
                return (variant, m)
            }
        }
        return nil
    }

    /// Lightweight normalized Levenshtein similarity in 0...1 (alphanumerics only).
    private func descriptionSimilarity(_ a: String, _ b: String) -> Double {
        func norm(_ s: String) -> [Character] {
            Array(s.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
                .map(Character.init))
        }
        let x = norm(a), y = norm(b)
        if x.isEmpty || y.isEmpty { return 0 }
        if x == y { return 1 }
        var prev = Array(0...y.count)
        var cur = [Int](repeating: 0, count: y.count + 1)
        for i in 1...x.count {
            cur[0] = i
            for j in 1...y.count {
                let cost = x[i - 1] == y[j - 1] ? 0 : 1
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
            }
            swap(&prev, &cur)
        }
        return 1.0 - Double(prev[y.count]) / Double(max(x.count, y.count))
    }

    /// Chooses the best description for a matched code: prefer the canonical DB
    /// description when the OCR text is empty/generic or is clearly the same
    /// description with OCR noise; otherwise keep the (often more specific) OCR text.
    private func reconcileDescription(ocr: String, canonical: String) -> String {
        let trimmed = ocr.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed.hasPrefix("Procedure ") || trimmed == "Unknown" { return canonical }
        if descriptionSimilarity(trimmed, canonical) >= 0.70 { return canonical }
        return trimmed
    }

    /// Valid US state / territory codes, for address state-abbreviation correction.
    private static let usStateCodes: Set<String> = [
        "AL","AK","AZ","AR","CA","CO","CT","DE","FL","GA","HI","ID","IL","IN","IA",
        "KS","KY","LA","ME","MD","MA","MI","MN","MS","MO","MT","NE","NV","NH","NJ",
        "NM","NY","NC","ND","OH","OK","OR","PA","RI","SC","SD","TN","TX","UT","VT",
        "VA","WA","WV","WI","WY","DC","PR","VI","GU"
    ]

    private static let ocrLetterConfusions: [Character: [Character]] = [
        "R": ["L","P","K","B"], "L": ["R","I","E"], "I": ["L","T"],
        "O": ["Q","D","C"], "B": ["R","E"], "G": ["C"], "C": ["G","O"],
        "D": ["O"], "U": ["V"], "V": ["U","Y"], "N": ["M","H"], "M": ["N"],
        "E": ["F","B"], "F": ["E","P"], "P": ["F","R"], "T": ["I","Y"],
        "Y": ["V","T"], "K": ["R","X"], "S": ["B"], "Q": ["O"]
    ]

    private func ocrLetterVariants(_ token: String) -> [String] {
        let chars = Array(token.uppercased())
        var out: [String] = []
        for i in chars.indices {
            guard let subs = Self.ocrLetterConfusions[chars[i]] else { continue }
            for s in subs where s.isLetter {
                var v = chars; v[i] = s; out.append(String(v))
            }
        }
        var seen = Set<String>([token.uppercased()])
        return out.filter { seen.insert($0).inserted }
    }

    /// Fixes a misread 2-letter state code that precedes a ZIP, e.g.
    /// "Orlando, FR 32806" → "Orlando, FL 32806" (OCR L→R).
    private func correctStateCode(in address: String) -> String {
        let pattern = #"\b([A-Za-z]{2})\s+(\d{5}(?:-\d{4})?)\b"#
        guard let re = try? NSRegularExpression(pattern: pattern) else { return address }
        let ns = address as NSString
        guard let m = re.firstMatch(in: address, range: NSRange(location: 0, length: ns.length)) else { return address }
        let stateRange = m.range(at: 1)
        let state = ns.substring(with: stateRange).uppercased()
        if Self.usStateCodes.contains(state) { return address }
        for variant in ocrLetterVariants(state) where Self.usStateCodes.contains(variant) {
            return ns.replacingCharacters(in: stateRange, with: variant)
        }
        return address
    }

    // MARK: - Account Statement Line Item Parser (multi-column format)

    /// Parses procedure line items from an account-statement bill (e.g. West Volusia).
    ///
    /// Account statement format groups charges by visit/voucher.  Each voucher contains:
    ///  - Procedure rows: date + code + description + charge amount
    ///  - Accounting rows: insurance payments, adjustments, patient payments
    ///  - A "Visit Total" row with the net patient responsibility
    ///
    /// This parser:
    ///  1. Skips accounting/payment rows (using `layout.accountingRowKeywords`)
    ///  2. Extracts CPT-coded procedure rows with their charge amounts
    ///  3. Sums Visit Total lines to compute total patient responsibility
    ///  4. Falls back to "Patient Balance:" at the bottom of the statement
    private func parseAccountStatementLineItems(layout: ProcedureColumnLayout) {
        let lines = procedureText.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var items: [ParsedLineItem] = []
        var visitTotalSum: Double = 0

        // Money tokens REQUIRE decimals, so dates ("07/11/11") and codes/vouchers are
        // never mistaken for a charge (this is what caused the bogus $7.00 / $10.00 —
        // the old "first number" grabbed "07" from the date). Preserves sign.
        func moneyValues(in line: String) -> [Double] {
            let pattern = #"-?\$?\s*\d{1,3}(?:,\d{3})*\.\d{2}\b"#
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
            let ns = line as NSString
            return regex.matches(in: line, range: NSRange(location: 0, length: ns.length)).compactMap {
                let raw = ns.substring(with: $0.range)
                guard let v = normalizeAmountToken(raw) else { return nil }
                return raw.contains("-") ? -abs(v) : v
            }
        }

        // First valid CPT (5-digit in range) or HCPCS code on a line.
        func firstCPT(in line: String) -> String? {
            if let r = line.range(of: #"\b\d{5}\b"#, options: .regularExpression) {
                let c = String(line[r])
                if let n = Int(c), n >= 10000 && n <= 99499 { return c }
            }
            if let r = line.range(of: #"\b[A-Z]\d{4}\b"#, options: .regularExpression) {
                return String(line[r])
            }
            return nil
        }

        // Human-readable label for a payment/credit row from the keywords present.
        func paymentLabel(from line: String) -> String {
            let l = line.lowercased()
            if l.contains("adjustment") || l.contains("contractual") || l.contains("write off") || l.contains("write-off") {
                return "Insurance Adjustment"
            }
            if l.contains("transfer")            { return "Transfer" }
            if l.contains("self pay") || l.contains("master card") || l.contains("credit card") || l.contains("mastercard") || l.contains("visa") {
                return "Self-Pay / Card Payment"
            }
            if l.contains("refund")              { return "Refund" }
            if l.contains("payment")             { return "Insurance Payment" }
            return "Payment / Credit"
        }

        for line in lines {
            let lower = line.lowercased()

            // ── Skip headers / patient / contact rows ──
            if lower.hasPrefix("date") && (lower.contains("code") || lower.contains("reason")
                || lower.contains("activity") || lower.contains("description")) { continue }
            if lower.hasPrefix("patient:") { continue }
            // Statement header/contact row (carries the office phone + account #)
            if line.range(of: #"\(?\d{3}\)?[-.\s]?\d{3}[-.\s]\d{4}"#, options: .regularExpression) != nil { continue }

            // ── Skip footer / instruction junk ──
            if lower.contains("return this portion") || lower.contains("reverse side")
                || lower.contains("indicate address") || lower.contains("show amount") { continue }

            // ── Explicit summary labels ──
            if lower.contains("total charge") || lower.contains("charges total") {
                if let amt = moneyValues(in: line).max() {
                    totalCharges = String(format: "%.2f", amt)
                    if billedAmount.isEmpty { billedAmount = totalCharges }
                }
                continue
            }
            if lower.contains("insurance paid") || lower.contains("ins paid") {
                if let amt = moneyValues(in: line).first(where: { $0 != 0 }) {
                    insurancePaid = String(format: "%.2f", abs(amt))
                }
                continue
            }
            if lower.contains("patient balance") || lower.contains("amount due") || lower.contains("balance due") {
                if let amt = moneyValues(in: line).last(where: { $0 > 0 }) {
                    amountDue = String(format: "%.2f", amt)
                }
                continue
            }

            let money = moneyValues(in: line)

            // ── CPT row → CHARGE (first positive money = Charges & Debits column) ──
            if let cpt = firstCPT(in: line) {
                let charge = money.first(where: { $0 > 0 }) ?? 0
                let description = extractStatementDescription(from: line, code: cpt)
                items.append(ParsedLineItem(code: cpt, description: description,
                                            amount: charge, codeType: classifyCodeType(cpt)))
                // Any negative merged onto this row is a credit.
                for c in money.filter({ $0 < 0 }) {
                    items.append(ParsedLineItem(code: "", description: paymentLabel(from: line),
                                                amount: c, isSelected: false, kind: .payment))
                }
                continue
            }

            // ── A NEGATIVE amount anywhere is a credit/payment — regardless of which
            //    line OCR scattered it onto (incl. ones misplaced onto a Visit Total
            //    row). This is robust to the heavy column-merging in these statements. ──
            let negatives = money.filter { $0 < 0 }
            if !negatives.isEmpty {
                let label = paymentLabel(from: line)
                for n in negatives {
                    items.append(ParsedLineItem(code: "", description: label,
                                                amount: n, isSelected: false, kind: .payment))
                }
                continue
            }

            // ── A genuine (positive) Visit Total = patient responsibility ──
            if lower.contains("visit total") {
                if let amt = money.last(where: { $0 > 0 }) { visitTotalSum += amt }
                continue
            }
        }

        lineItems = items

        let chargesSum = items.filter { $0.kind == .charge }.reduce(0) { $0 + $1.amount }
        let creditsSum = items.filter { $0.kind == .payment }.reduce(0) { $0 + $1.amount }

        if amountDue.isEmpty {
            if visitTotalSum > 0 {
                amountDue = String(format: "%.2f", visitTotalSum)
            } else {
                // Patient owes charges minus credits (credits are stored negative).
                let bal = chargesSum + creditsSum
                if bal >= 0 { amountDue = String(format: "%.2f", bal) }
            }
        }
        if billedAmount.isEmpty {
            billedAmount = !totalCharges.isEmpty ? totalCharges
                : (chargesSum > 0 ? String(format: "%.2f", chargesSum) : amountDue)
        }

        #if DEBUG
        let c = items.filter { $0.kind == .charge }.count
        let p = items.filter { $0.kind == .payment }.count
        print("── AccountStatement: \(c) charges, \(p) credits, chargesSum=\(chargesSum), creditsSum=\(creditsSum), amountDue=\(amountDue)")
        #endif
    }

    /// Returns the first dollar-formatted amount found on a line.
    /// Used to extract the "Charges & Debits" column (leftmost dollar value).
    private func extractFirstDollarAmount(from text: String) -> Double? {
        let pattern = #"\$?\s*([0-9][0-9.,]*)"#
        guard let match = text.range(of: pattern, options: .regularExpression) else { return nil }
        return normalizeAmountToken(String(text[match]))
    }

    /// Returns the LAST dollar-formatted amount found on a line.
    /// Used to extract the "Patient Amount" column (rightmost dollar value).
    private func extractLastDollarAmount(from text: String) -> Double? {
        let pattern = #"\$?\s*([0-9][0-9.,]*)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: range)
        guard let last = matches.last,
              let r = Range(last.range(at: 1), in: text) else { return nil }
        return normalizeAmountToken(String(text[r]))
    }

    /// Extracts the first 5-digit CPT code or HCPCS code from a statement line.
    private func extractFirstMedicalCode(from line: String) -> String {
        // 5-digit CPT: 10000–99499
        if let range = line.range(of: #"\b[0-9]{5}\b"#, options: .regularExpression) {
            let candidate = String(line[range])
            if let n = Int(candidate), n >= 10000 && n <= 99499 { return candidate }
        }
        // HCPCS: letter + 4 digits (e.g. J2175)
        if let range = line.range(of: #"\b[A-Z][0-9]{4}\b"#, options: .regularExpression) {
            return String(line[range])
        }
        return ""
    }

    /// Extracts the description portion of a statement line (between the code and first dollar).
    private func extractStatementDescription(from line: String, code: String) -> String {
        var work = line
        // Remove leading date
        if let dateEnd = work.range(of: #"^\d{1,2}[/\-]\d{1,2}[/\-]\d{2,4}\s*"#, options: .regularExpression) {
            work = String(work[dateEnd.upperBound...])
        }
        // Remove the code if present
        if !code.isEmpty, let codeRange = work.range(of: code) {
            work = String(work[codeRange.upperBound...]).trimmingCharacters(in: .whitespaces)
        }
        // Take everything up to the first dollar amount or digit sequence that looks like a column value
        if let amtRange = work.range(of: #"\s+\$?[\d,]+\.?\d{0,2}"#, options: .regularExpression) {
            work = String(work[work.startIndex..<amtRange.lowerBound])
        }
        return work.trimmingCharacters(in: .whitespaces)
    }

    /// Look up each line item's code in the medical code database
    private func lookupLineItemCodes() {
        let cloudKit = appState.cloudKitService
        
        for i in lineItems.indices {
            guard lineItems[i].kind == .charge else { continue }   // payments/credits carry no code
            let code = lineItems[i].code
            guard !code.isEmpty else { continue }

            // Classify the code type
            lineItems[i].codeType = classifyCodeType(code)

            // Look up in the database — tries OCR-confusion variants if the
            // direct match fails (e.g. "98223" → "99223").
            if let result = databaseMatch(forCode: code, ocrDescription: lineItems[i].description, using: cloudKit) {
                if result.code != code.uppercased() {
                    lineItems[i].code = result.code   // adopt the OCR-corrected code
                    #if DEBUG
                    print("  ✏️ OCR-corrected code \(code) → \(result.code)")
                    #endif
                }
                lineItems[i].matchedMedicalCode = result.match
                lineItems[i].codeType = result.match.codeType
                lineItems[i].lookupFailed = false

                // Prefer the canonical description when OCR is empty/generic or is
                // the same description with OCR noise ("Inital" → "Initial"); keep
                // a more-specific OCR description otherwise.
                lineItems[i].description = reconcileDescription(
                    ocr: lineItems[i].description,
                    canonical: result.match.shortDescription
                )

                #if DEBUG
                print("  🔍 \(result.code) → \(result.match.shortDescription) [\(result.match.codeType.rawValue)]")
                #endif
            } else {
                lineItems[i].lookupFailed = true
                #if DEBUG
                print("  🔍 \(code) → not found in database")
                #endif
            }
        }
        
        // Also scan the full procedure text for additional codes not captured as line items
        scanForAdditionalCodes()
    }
    
    /// Scan procedure + insurance text for medical codes that weren't captured as line items
    private func scanForAdditionalCodes() {
        let allText = (procedureText + "\n" + insuranceText).uppercased()
        let existingCodes = Set(lineItems.map { $0.code.uppercased() })
        let cloudKit = appState.cloudKitService
        
        // Regex patterns from ScannerViewModel
        let patterns: [(String, MedicalCodeType)] = [
            (#"\b([A-V]\d{4})\b"#, .hcpcs),
            (#"\b(\d{5})\b"#, .cpt),
            (#"\b([A-TV-Z]\d{2}(?:\.\d{1,4})?)\b"#, .icd10)
        ]
        
        var newItems: [ParsedLineItem] = []
        
        for (pattern, codeType) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let matches = regex.matches(in: allText, range: NSRange(allText.startIndex..., in: allText))
            
            for match in matches {
                guard let range = Range(match.range(at: 1), in: allText) else { continue }
                let code = String(allText[range])
                
                // Skip if already a line item or invalid
                guard !existingCodes.contains(code) else { continue }
                guard classifyCodeType(code) != nil else { continue }
                
                // For CPT, reject if < 10000
                if codeType == .cpt, let num = Int(code), num < 10000 { continue }

                // Context-aware false-positive rejection for 5-digit "CPT" matches:
                // ZIP codes (FL 32720 / 32720-0824) and account/voucher numbers are
                // 5 digits too and otherwise get mistaken for procedure codes.
                if codeType == .cpt {
                    let ns = allText as NSString
                    let loc = match.range(at: 1).location
                    let len = match.range(at: 1).length
                    let preStart = max(0, loc - 28)
                    let pre = ns.substring(with: NSRange(location: preStart, length: loc - preStart))
                    let postLen = min(6, ns.length - (loc + len))
                    let post = ns.substring(with: NSRange(location: loc + len, length: postLen))
                    // ZIP+4 (e.g. 32720-0824)
                    if post.range(of: #"^-\d{4}"#, options: .regularExpression) != nil { continue }
                    // ZIP preceded by a 2-letter US state abbreviation (…DELAND FL 32720)
                    let preTrim = pre.trimmingCharacters(in: .whitespaces)
                    if preTrim.count >= 2, Self.usStateCodes.contains(String(preTrim.suffix(2))) { continue }
                    // Account / voucher / balance / statement / phone context
                    if ["ACCOUNT", "ACCT", "VOUCHER", "BALANCE", "ZIP", "PHONE",
                        "STATEMENT", "PAGE", "PORTION", "#"]
                        .contains(where: { pre.contains($0) }) { continue }
                    // Account number sitting right after a phone number (…943-7100  STATEMENT  38142)
                    if pre.range(of: #"\d{3}[-.\s]\d{4}"#, options: .regularExpression) != nil { continue }
                }

                // Avoid duplicates in new items
                guard !newItems.contains(where: { $0.code == code }) else { continue }
                
                // Look up in database
                let matched = cloudKit.lookupCode(code)
                let desc = matched?.shortDescription ?? "Detected \(codeType.rawValue) code"
                
                let item = ParsedLineItem(
                    code: code,
                    description: desc,
                    amount: 0,
                    isSelected: false,  // Not auto-selected — user decides
                    codeType: codeType,
                    matchedMedicalCode: matched,
                    lookupFailed: matched == nil
                )
                
                newItems.append(item)
                
                #if DEBUG
                print("  🆕 Additional code: \(code) → \(desc)")
                #endif
            }
        }
        
        if !newItems.isEmpty {
            lineItems.append(contentsOf: newItems)
        }
    }
    
    // MARK: - Import from Code Scanner
    
    /// Convert ScannedCode objects from ScannerView into ParsedLineItems and add to bill
    private func importScannedCodes(_ scannedCodes: [ScannedCode]) {
        let existingCodes = Set(lineItems.map { $0.code.uppercased() })
        var newItems: [ParsedLineItem] = []
        
        for sc in scannedCodes {
            let code = sc.detectedCode.uppercased()
            guard !existingCodes.contains(code) else { continue }
            guard !newItems.contains(where: { $0.code.uppercased() == code }) else { continue }
            
            let codeType = sc.possibleType ?? classifyCodeType(code)
            let description = sc.matchedMedicalCode?.shortDescription
                ?? (sc.scannedDescription.isEmpty ? "Scanned code" : sc.scannedDescription)
            
            let item = ParsedLineItem(
                code: code,
                description: description,
                amount: sc.scannedPrice ?? 0,
                isSelected: true,
                codeType: codeType,
                matchedMedicalCode: sc.matchedMedicalCode,
                lookupFailed: sc.lookupFailed
            )
            newItems.append(item)
        }
        
        if !newItems.isEmpty {
            lineItems.append(contentsOf: newItems)
            #if DEBUG
            print("📥 Imported \(newItems.count) codes from scanner: \(newItems.map(\.code))")
            #endif
        }
    }
    
    // MARK: - Parsing Helpers
    
    /// Known labels for multi-label splitting — ordered longest first to avoid partial matches
    private static let knownLabels: [(pattern: String, key: String)] = [
        ("patient name", "patient name"), ("patient address", "patient address"),
        ("patient", "patient"), ("name", "name"),
        ("insured name", "insured name"), ("insured", "insured"),
        ("subscriber", "subscriber"),
        ("account number", "account number"), ("account #", "account #"),
        ("account no", "account no"), ("acct #", "acct #"), ("account", "account"),
        ("date of service", "date of service"), ("date(s) of service", "date of service"),
        ("service date", "service date"), ("dos", "dos"),
        ("date of birth", "date of birth"), ("dob", "dob"),
        ("mrn", "mrn"), ("medical record number", "mrn"), ("medical record", "mrn"),
        ("discharge date", "discharge date"), ("discharged", "discharge date"),
        ("date of discharge", "discharge date"), ("disch date", "discharge date"),
        ("admit date", "admit date"), ("admission date", "admit date"),
        ("date of admission", "admit date"), ("admitted", "admit date"),
        ("insurance company", "insurance company"), ("insurance", "insurance"),
        ("carrier", "carrier"), ("payer", "payer"),
        ("policy number", "policy number"), ("policy #", "policy #"),
        ("policy no", "policy no"), ("policy", "policy"),
        ("member id", "member id"), ("member #", "member #"), ("member", "member"),
        ("subscriber id", "subscriber id"), ("id #", "id #"),
        ("group number", "group number"), ("group #", "group #"),
        ("group no", "group no"), ("group", "group"),
        ("plan type", "plan type"), ("plan name", "plan name"),
        ("provider", "provider"), ("facility", "facility"),
        ("hospital", "hospital"), ("clinic", "clinic"),
        ("remit to", "remit to"), ("pay to", "remit to"), ("send to", "remit to"),
        ("return to", "remit to"), ("bill to", "remit to"),
        ("office phone number", "office phone"), ("office phone", "office phone"),
        ("phone number", "phone"), ("phone", "phone"), ("tel", "tel"), ("telephone", "telephone"),
        ("fax", "fax"), ("npi", "npi"), ("address", "address"),
        ("voucher", "voucher"),
        ("statement date", "statement date"), ("due date", "due date"),
        ("patient balance", "patient balance"),
        ("email", "email"), ("e-mail", "email"),
        ("website", "website"), ("web", "website"), ("url", "website"),
        ("tax id", "tax id"), ("tax identification", "tax id"), ("ein", "ein"),
        ("federal id", "tax id"), ("fed id", "tax id"),
        ("license number", "license"), ("license #", "license"),
        ("license no", "license"), ("lic #", "license"), ("lic", "license"),
        ("total charges", "total charges"), ("amount due", "amount due"),
        ("insurance paid", "insurance paid"), ("insurance adjustment", "insurance adjustment"),
    ]
    
    /// Extract ALL label:value pairs from lines, splitting multi-label lines
    /// e.g. "Patient: Michael R. Thompson  Account #: ACCT-2024-78452"
    /// → [("patient", "Michael R. Thompson"), ("account #", "ACCT-2024-78452")]
    private func extractAllLabelValuePairs(from lines: [String]) -> [(String, String)] {
        var pairs: [(String, String)] = []
        
        for line in lines {
            let lower = line.lowercased()
            
            // Find all recognized label positions in this line
            var labelPositions: [(pos: Int, len: Int, key: String)] = []
            
            for (pattern, key) in Self.knownLabels {
                var searchStart = lower.startIndex
                while let range = lower.range(of: pattern, range: searchStart..<lower.endIndex) {
                    // Check that a colon follows (possibly with whitespace)
                    let afterLabel = lower[range.upperBound...].trimmingCharacters(in: .whitespaces)
                    guard afterLabel.hasPrefix(":") || lower[range.upperBound...].hasPrefix(":") else {
                        searchStart = range.upperBound; continue
                    }
                    
                    let pos = lower.distance(from: lower.startIndex, to: range.lowerBound)
                    // Find the colon position
                    let colonSearchStart = range.upperBound
                    guard let colonRange = lower.range(of: ":", range: colonSearchStart..<lower.endIndex) else {
                        searchStart = range.upperBound; continue
                    }
                    let colonPos = lower.distance(from: lower.startIndex, to: colonRange.upperBound)
                    let len = colonPos - pos
                    
                    // Don't add if overlaps with a longer label at same position
                    if !labelPositions.contains(where: { $0.pos == pos && $0.len >= len }) {
                        labelPositions.removeAll { $0.pos == pos && $0.len < len }
                        labelPositions.append((pos, len, key))
                    }
                    searchStart = colonRange.upperBound
                }
            }
            
            if labelPositions.isEmpty {
                // No recognized labels — try generic "Word: Value" pattern
                if let colonRange = line.range(of: ":") {
                    let label = String(line[line.startIndex..<colonRange.lowerBound]).trimmingCharacters(in: .whitespaces)
                    let value = String(line[colonRange.upperBound...]).trimmingCharacters(in: .whitespaces)
                    if !label.isEmpty && label.count <= 30 && !value.isEmpty {
                        pairs.append((label, value))
                    }
                }
                continue
            }
            
            // Sort by position and extract values
            labelPositions.sort { $0.pos < $1.pos }

            let lineCount = line.count
            for (idx, lp) in labelPositions.enumerated() {
                // Guard: valueStart must not exceed the line length
                let startOffset = min(lp.pos + lp.len, lineCount)
                let valueStart  = line.index(line.startIndex, offsetBy: startOffset)

                let valueEnd: String.Index
                if idx + 1 < labelPositions.count {
                    // Guard: valueEnd must not precede valueStart (overlapping labels)
                    let endOffset = min(
                        max(labelPositions[idx + 1].pos, startOffset),
                        lineCount
                    )
                    valueEnd = line.index(line.startIndex, offsetBy: endOffset)
                } else {
                    valueEnd = line.endIndex
                }

                // Final safety net — skip silently if range is somehow still inverted
                guard valueStart <= valueEnd else { continue }

                let value = String(line[valueStart..<valueEnd]).trimmingCharacters(in: .whitespaces)
                if !value.isEmpty {
                    pairs.append((lp.key, value))
                }
            }
        }
        
        return pairs
    }
    
    private func parseDate(_ text: String) -> Date? {
        let formatters = [
            "MM/dd/yyyy", "M/d/yyyy", "MM/dd/yy", "M/d/yy",
            "yyyy-MM-dd", "MM-dd-yyyy", "M-d-yy"
        ]
        for fmt in formatters {
            let df = DateFormatter()
            df.dateFormat = fmt
            df.locale = Locale(identifier: "en_US_POSIX")
            if let date = df.date(from: text.trimmingCharacters(in: .whitespaces)) {
                return date
            }
        }
        return nil
    }
    
    private func looksLikeName(_ text: String) -> Bool {
        let words = text.split(separator: " ")
        if words.count < 2 || words.count > 5 { return false }
        return text.rangeOfCharacter(from: .decimalDigits) == nil && words.allSatisfy { $0.first?.isLetter == true }
    }
    
    private func looksLikeAddress(_ text: String) -> Bool {
        let upper = text.uppercased()
        let indicators = ["STREET", "ST.", "ST ", "AVE", "AVENUE", "BLVD", "DRIVE", "DR.", "DR ",
                          "ROAD", "RD.", "RD ", "LANE", "LN.", "LN ", "WAY", "SUITE", "STE",
                          "P.O. BOX", "PO BOX", "P O BOX", "COURT", "CT.", "CT ",
                          "CIRCLE", "CIR", "PLACE", "PL.", "PIKE", "HWY", "HIGHWAY",
                          "NORTH ", "SOUTH ", "EAST ", "WEST ", " N ", " S ", " E ", " W "]
        if indicators.contains(where: { upper.contains($0) }) { return true }
        if text.first?.isNumber == true && text.count > 10 { return true }
        return text.range(of: #"\b\d{5}(-\d{4})?\b"#, options: .regularExpression) != nil
    }
    
    private func looksLikePhone(_ text: String) -> Bool {
        let digits = text.filter { $0.isNumber }
        return digits.count >= 10 && digits.count <= 11
    }

    /// True if a line looks like a file name or document-viewer window chrome
    /// (e.g. "12_Routine_Phys… 1 page", "Invoice_2024.pdf", "Scan — Preview")
    /// rather than a real provider/business name. Used to keep on-screen capture
    /// artifacts from being mistaken for the facility name.
    private func looksLikeFilename(_ raw: String) -> Bool {
        let s = raw.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return false }
        let lower = s.lowercased()

        // 1. A document/image/file extension anywhere in the line.
        let exts = [".pdf", ".png", ".jpg", ".jpeg", ".heic", ".heif", ".tiff", ".tif",
                    ".gif", ".bmp", ".webp", ".doc", ".docx", ".pages", ".numbers",
                    ".txt", ".rtf", ".key", ".ppt", ".pptx", ".xls", ".xlsx"]
        if exts.contains(where: { lower.contains($0) }) { return true }

        // 2. Viewer window chrome: "1 page", "2 of 5 pages", app names.
        if lower.range(of: #"\b\d+\s+of\s+\d+\s+pages?\b"#, options: .regularExpression) != nil { return true }
        if lower.range(of: #"\b\d+\s+pages?\b"#, options: .regularExpression) != nil { return true }
        let viewerWords = ["preview", "adobe", "acrobat", "quick look", "quicklook", "— pdf", "- pdf"]
        if viewerWords.contains(where: { lower.contains($0) }) { return true }

        // 3. Ellipsis-truncated title-bar token (e.g. "12_Routine_Phys…").
        if (s.contains("…") || s.hasSuffix("...")) && s.split(separator: " ").count <= 2 { return true }

        // 4. Underscore-joined filename tokens with little or no spacing.
        let spaceCount = s.filter { $0 == " " }.count
        let underscoreCount = s.filter { $0 == "_" }.count
        if underscoreCount >= 1 && spaceCount <= 1 { return true }

        return false
    }

    /// True if a line looks like a charges-table / procedure row rather than a
    /// facility name — e.g. "10/10/24  99223  Initial Hospital Care   $1,450.00".
    /// Critical because CPT descriptions like "Initial Hospital Care",
    /// "Subsequent Hospital Care", and "Hospital Discharge Day" all contain the
    /// facility keyword "HOSPITAL" and would otherwise be mistaken for the provider.
    private func looksLikeProcedureRow(_ raw: String) -> Bool {
        let s = raw.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return false }
        // Starts with a service date or date range: 10/10/24, 10/10/2024, 10/11-16
        if s.range(of: #"^\d{1,2}/\d{1,2}(/\d{2,4}|-\d{1,2})"#, options: .regularExpression) != nil { return true }
        // Contains a standalone 5-digit CPT code
        if s.range(of: #"\b\d{5}\b"#, options: .regularExpression) != nil { return true }
        // Contains a HCPCS code (letter + 4 digits, e.g. J2175)
        if s.range(of: #"\b[A-Z]\d{4}\b"#, options: .regularExpression) != nil { return true }
        // Contains a dollar amount (charge column)
        if s.range(of: #"\$\s?\d"#, options: .regularExpression) != nil { return true }
        return false
    }
    
    private func extractProcedureCode(from text: String) -> String? {
        // CPT codes: 5 digits (99284, 71046, etc.)
        // HCPCS codes: letter + 4 digits (J2175, etc.)
        // Revenue codes: 4 digits (0121, 0112, etc.) — hospital UB-04 billing
        // ICD-10: letter + 2-4 digits with optional dot (A01.1, M54.5)
        let patterns = [
            #"\b([A-Z]\d{4})\b"#,          // HCPCS: J2175
            #"\b(\d{5})\b"#,                // CPT: 99284
            #"\b(0\d{3})\b"#,               // Revenue code: 0121 (starts with 0, 4 digits)
            #"\b([A-Z]\d{2,4}\.?\d{0,2})\b"# // ICD-10: M54.5
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let range = Range(match.range(at: 1), in: text) {
                let code = String(text[range])
                
                // Reject if the code is part of a longer digit sequence (account #, date, etc.)
                if range.lowerBound > text.startIndex {
                    let before = text[text.index(before: range.lowerBound)]
                    if before.isNumber { continue }
                }
                if range.upperBound < text.endIndex {
                    let after = text[range.upperBound]
                    if after.isNumber { continue }
                }
                
                // Reject ZIP codes (5 digits preceded by state abbreviation)
                if code.allSatisfy(\.isNumber), code.count == 5 {
                    let beforeCode = String(text[text.startIndex..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
                    if beforeCode.count >= 2 {
                        let lastTwo = String(beforeCode.suffix(2)).uppercased()
                        let states: Set<String> = ["AL","AK","AZ","AR","CA","CO","CT","DE","FL","GA","HI","ID",
                                                   "IL","IN","IA","KS","KY","LA","ME","MD","MA","MI","MN","MS",
                                                   "MO","MT","NE","NV","NH","NJ","NM","NY","NC","ND","OH","OK",
                                                   "OR","PA","RI","SC","SD","TN","TX","UT","VT","VA","WA","WV","WI","WY"]
                        if states.contains(lastTwo) { continue }
                    }
                    
                    if let num = Int(code) {
                        if num < 10000 { continue }
                    }
                }
                
                return code
            }
        }
        return nil
    }
    
    /// Extract dollar amount — REQUIRES "$" sign to avoid matching dates (11/15/24 → 24)
    /// Parses a money token into a Double, tolerating OCR that misreads a thousands
    /// comma as a period (so "$22,500.00" arrives as "22.500.00"). Rule: unify "," and
    /// "." to a single separator; the LAST group is the decimal only if it has ≤2 digits,
    /// otherwise every separator is a thousands separator (no decimal).
    ///   "22,500.00" / "22.500.00" → 22500.00      "3.850.00" → 3850.00
    ///   "245.00" → 245.00          "1.500" → 1500   "22.50" → 22.50
    private func normalizeAmountToken(_ raw: String) -> Double? {
        var s = raw.replacingOccurrences(of: "$", with: "")
                   .replacingOccurrences(of: " ", with: "")
                   .trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return nil }
        let negative = s.hasPrefix("-")
        if negative { s.removeFirst() }
        s = s.replacingOccurrences(of: ",", with: ".")
        let parts = s.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else { return nil }

        let intPart: String
        let fracPart: String
        if parts.count == 1 {
            intPart = parts[0]; fracPart = ""
        } else if let last = parts.last, last.count <= 2 {
            fracPart = last; intPart = parts.dropLast().joined()
        } else {
            intPart = parts.joined(); fracPart = ""
        }
        let combined = fracPart.isEmpty ? intPart : "\(intPart).\(fracPart)"
        guard let val = Double(combined) else { return nil }
        return negative ? -val : val
    }

    private func extractStrictDollarAmount(from text: String) -> Double? {
        // "$" then a run of digits and grouping separators (commas, or OCR-misread
        // periods). normalizeAmountToken sorts out thousands vs decimal.
        let pattern = #"-?\$\s*([0-9][0-9.,]*)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)

        var amounts: [Double] = []
        for match in regex.matches(in: text, range: range) {
            if let r = Range(match.range(at: 1), in: text),
               let amount = normalizeAmountToken(String(text[r])), amount > 0 {
                amounts.append(amount)
            }
        }
        // Return the largest amount (most likely the charge, not quantity)
        return amounts.max()
    }
    
    /// Extract a plain decimal amount (no "$" required) — used as fallback
    /// Only matches numbers with exactly 2 decimal places to avoid matching dates, quantities, etc.
    private func extractPlainAmount(from text: String) -> Double? {
        // Match numbers like 15,000.00 or 245.00 — must have .XX decimal
        let pattern = #"\b(\d{1,3}(?:,\d{3})*\.\d{2})\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: range)
        
        var amounts: [Double] = []
        for match in matches {
            guard let r = Range(match.range(at: 1), in: text) else { continue }
            let numStr = String(text[r]).replacingOccurrences(of: ",", with: "")
            guard let val = Double(numStr), val > 0.99 else { continue }  // Skip tiny values (likely not charges)
            
            // Reject if it looks like a date (e.g., 10/15/2024 → "2024" won't match .XX pattern, but 10.15 could)
            // Check that there's no "/" immediately before or after
            if match.range.location > 0 {
                let nsText = text as NSString
                let charBefore = nsText.substring(with: NSRange(location: match.range.location - 1, length: 1))
                if charBefore == "/" { continue }
            }
            let endLoc = match.range.location + match.range.length
            if endLoc < (text as NSString).length {
                let charAfter = (text as NSString).substring(with: NSRange(location: endLoc, length: 1))
                if charAfter == "/" { continue }
            }
            
            amounts.append(val)
        }
        
        return amounts.max()
    }
    
    // MARK: - Scanned Name Parsing
    
    /// Split scanned patientName into first/last for Patient creation
    private var scannedFirstName: String {
        let parts = patientName.trimmingCharacters(in: .whitespaces).split(separator: " ")
        return parts.first.map(String.init) ?? ""
    }
    
    private var scannedLastName: String {
        let parts = patientName.trimmingCharacters(in: .whitespaces).split(separator: " ")
        if parts.count >= 2 {
            return parts.dropFirst().joined(separator: " ")
        }
        return ""
    }
    
    /// Check if scanned name matches a patient (case-insensitive, flexible)
    private func patientMatchesScannedName(_ patient: Patient) -> Bool {
        let scanned = patientName.lowercased().trimmingCharacters(in: .whitespaces)
        guard !scanned.isEmpty else { return true } // No scanned name = use current
        
        let full = patient.fullName.lowercased()
        let display = patient.displayName.lowercased()
        
        // Exact match
        if scanned == full || scanned == display { return true }
        
        // Contains match (handles "MARY M ARSENAULT" matching "Mary Arsenault")
        let scannedParts = Set(scanned.split(separator: " ").map(String.init))
        let patientParts = Set((full).split(separator: " ").map(String.init))
        
        // At least first and last name overlap
        let overlap = scannedParts.intersection(patientParts)
        if overlap.count >= 2 { return true }
        
        // Last name + first initial
        if patient.lastName.lowercased() == scannedLastName.lowercased()
            && !scannedFirstName.isEmpty
            && patient.firstName.lowercased().hasPrefix(scannedFirstName.lowercased().prefix(1)) {
            return true
        }
        
        return false
    }
    
    /// Find an existing patient whose name matches the scanned name
    private func findMatchingPatient() -> Patient? {
        guard !patientName.isEmpty else { return nil }
        return patientDataService.patients.first(where: { patientMatchesScannedName($0) })
    }
    
    // MARK: - Save Bill
    
    private func saveBill() {
        isSaving = true
        
        // ── Step 1: Resolve which patient this bill belongs to ──
        
        // No patients at all?
        if patientDataService.patients.isEmpty {
            isSaving = false
            showingNoPatientAlert = true
            return
        }
        
        // No patient selected?
        guard let currentPatientId = appState.selectedPatientId,
              let currentPatient = patientDataService.patients.first(where: { $0.id == currentPatientId }) else {
            // Try to find matching patient by name
            if let matched = findMatchingPatient() {
                resolvedPatientId = matched.id
                appState.selectPatient(matched.id)
                continueSaveBill()
            } else {
                isSaving = false
                showingNoPatientAlert = true
            }
            return
        }
        
        // Scanned name present but doesn't match current patient?
        if !patientName.isEmpty && !patientMatchesScannedName(currentPatient) {
            // Check if another existing patient matches
            matchedExistingPatient = patientDataService.patients.first(where: {
                $0.id != currentPatientId && patientMatchesScannedName($0)
            })
            isSaving = false
            showingPatientPrompt = true
            return
        }
        
        // Name matches or no scanned name — use current patient
        resolvedPatientId = currentPatientId
        continueSaveBill()
    }
    
    /// Create a new patient from scanned data and save the bill to them
    private func createPatientFromScanAndSave() {
        let first = scannedFirstName
        let last = scannedLastName
        
        guard !first.isEmpty, !last.isEmpty else {
            // Can't parse name — fall back to no-patient alert
            showingNoPatientAlert = true
            return
        }
        
        // Parse DOB if available
        var dob: Date?
        if !dateOfBirth.isEmpty {
            let formats = ["MM/dd/yyyy", "MM-dd-yyyy", "yyyy-MM-dd", "MM/dd/yy"]
            let formatter = DateFormatter()
            for fmt in formats {
                formatter.dateFormat = fmt
                if let d = formatter.date(from: dateOfBirth) { dob = d; break }
            }
        }
        
        // Parse address if available
        var addresses: [PatientAddress] = []
        if !patientAddress.isEmpty {
            addresses.append(PatientAddress(
                label: .home,
                street1: patientAddress,
                isPrimary: true
            ))
        }
        
        let patient = Patient(
            guardianUserId: UserManager.shared.currentUser?.id ?? "",
            firstName: first,
            lastName: last,
            dateOfBirth: dob,
            relationship: .other,
            addresses: addresses
        )
        
        patientDataService.savePatient(patient)
        appState.selectPatient(patient.id)
        resolvedPatientId = patient.id
        
        #if DEBUG
        print("👤 Created patient from scan: \(patient.displayName) (id: \(patient.id))")
        #endif
        
        isSaving = true
        continueSaveBill()
    }
    
    /// Continue saving once patient is resolved
    private func continueSaveBill() {
        guard let patientId = resolvedPatientId else {
            isSaving = false
            return
        }
        isSaving = true
        
        let totalAmount = Double(billedAmount) ?? lineItems.filter { $0.kind == .charge }.reduce(0) { $0 + $1.amount }

        // Build BillLineItems from parsed items with enriched data (charges only)
        let billLineItems: [BillLineItem] = lineItems.filter { $0.isSelected && $0.kind == .charge }.map { item in
            var notes: String? = nil
            if let mc = item.matchedMedicalCode, mc.hasValidPricing {
                notes = "Typical range: \(mc.formattedPriceRange)"
            }
            return BillLineItem(
                procedureCode: item.code.isEmpty ? nil : item.code,
                procedureDescription: item.bestDescription,
                serviceDate: serviceDate,
                quantity: 1,
                unitCharge: item.amount,
                totalCharge: item.amount,
                notes: notes
            )
        }
        
        // Split the parsed account-statement credits: self-pay / card credits go to
        // Patient Payments; insurer credits (adjustments, payments, transfers) go to
        // Insurance Payments. Stored as positive amounts; detail screens render them
        // as deductions.
        let scanCredits = lineItems.filter { $0.kind == .payment && abs($0.amount) > 0 }
        func isSelfPayCredit(_ label: String) -> Bool {
            let l = label.lowercased()
            return l.contains("self") || l.contains("card")   // self-pay / credit card / master card
        }
        let insurancePaymentsFromScan: [InsurancePayment] = scanCredits
            .filter { !isSelfPayCredit($0.description) }
            .map { item in
                InsurancePayment(
                    payerName: insuranceCarrier.isEmpty ? "Insurance" : insuranceCarrier,
                    amount: abs(item.amount),
                    paymentDate: serviceDate,
                    transactionType: .other,
                    notes: item.description.isEmpty ? "Payment / Credit" : item.description
                )
            }
        let patientPaymentsFromScan: [PatientPayment] = scanCredits
            .filter { isSelfPayCredit($0.description) }
            .map { item in
                PatientPayment(
                    amount: abs(item.amount),
                    paymentDate: serviceDate,
                    paymentMethod: .creditCard,
                    confirmationNumber: nil,
                    paidToProvider: providerName.isEmpty ? nil : providerName,
                    notes: item.description.isEmpty ? "Self-Pay / Card Payment" : item.description
                )
            }

        // Extract procedure codes using classified types
        let cptCodes = lineItems.filter(\.isSelected).compactMap { item -> String? in
            guard !item.code.isEmpty else { return nil }
            if let t = item.codeType { return (t == .cpt || t == .hcpcs) ? item.code : nil }
            return item.code.first?.isNumber == true ? item.code : nil
        }
        let diagCodes = lineItems.filter(\.isSelected).compactMap { item -> String? in
            guard !item.code.isEmpty else { return nil }
            if let t = item.codeType { return (t == .icd10 || t == .icd10pcs) ? item.code : nil }
            return item.code.first?.isLetter == true ? item.code : nil
        }
        
        // Build notes with supplementary fields
        var notesParts: [String] = []
        if !patientAddress.isEmpty { notesParts.append("Patient Address: \(patientAddress)") }
        if !dateOfBirth.isEmpty { notesParts.append("DOB: \(dateOfBirth)") }
        if !mrn.isEmpty { notesParts.append("MRN: \(mrn)") }
        if !dischargeDate.isEmpty { notesParts.append("Discharge Date: \(dischargeDate)") }
        if !insurancePlanType.isEmpty { notesParts.append("Plan Type: \(insurancePlanType)") }
        
        // ── Create or find Provider with full address ──
        Task { @MainActor in
            let providerId = await createOrUpdateProvider()
            
            // ── Create or find Insurance Policy from scanned data ──
            let policyId = createOrFindInsurancePolicy(patientId: patientId)
            
            let claim = Claim(
                patientId: patientId,
                policyId: policyId ?? (policyNumber.isEmpty ? memberId : policyNumber),
                providerId: providerId,
                providerName: providerName.isEmpty ? nil : providerName,
                claimNumber: accountNumber.isEmpty ? nil : accountNumber,
                status: .notSubmitted,
                serviceDate: serviceDate,
                billedAmount: totalAmount,
                patientResponsibility: Double(amountDue) ?? totalAmount,
                procedureCodes: cptCodes.isEmpty ? nil : cptCodes,
                diagnosisCodes: diagCodes.isEmpty ? nil : diagCodes,
                notes: notesParts.isEmpty ? nil : notesParts.joined(separator: "\n"),
                lineItems: billLineItems,
                insurancePayments: insurancePaymentsFromScan,
                patientPayments: patientPaymentsFromScan.isEmpty ? nil : patientPaymentsFromScan,
                createdAt: Date(),
                updatedAt: Date()
            )
            
            // ── Check for duplicate before saving ──
            if let existing = patientDataService.findDuplicateClaim(
                patientId: patientId,
                providerName: providerName.isEmpty ? nil : providerName,
                claimNumber: accountNumber.isEmpty ? nil : accountNumber,
                serviceDate: serviceDate,
                billedAmount: totalAmount
            ) {
                // Duplicate found — ask user what to do
                duplicateClaim = existing
                pendingClaim = claim
                pendingProviderId = providerId
                isSaving = false
                showingDuplicateAlert = true
            } else {
                // No duplicate — save directly
                patientDataService.saveClaim(claim)
                savedClaimId = claim.id
                isSaving = false
                saveResult = .scanMore
            }
        }
    }
    
    /// Replace the existing duplicate with the new scanned bill
    private func replaceExistingClaim() {
        guard var claim = pendingClaim, let existing = duplicateClaim else { return }
        isSaving = true
        
        // Preserve any user-entered data from the old claim that's missing from the scan
        // (e.g., if the old claim had insurance payments recorded, carry them forward)
        if claim.insurancePayments.isEmpty && !existing.insurancePayments.isEmpty {
            claim.insurancePayments = existing.insurancePayments
        }
        if claim.paidAmount == nil { claim.paidAmount = existing.paidAmount }
        if claim.allowedAmount == nil { claim.allowedAmount = existing.allowedAmount }
        if claim.adjustmentAmount == nil { claim.adjustmentAmount = existing.adjustmentAmount }
        if claim.eobReceived == false && existing.eobReceived {
            claim.eobReceived = existing.eobReceived
            claim.eobDate = existing.eobDate
            claim.eobDocumentId = existing.eobDocumentId
        }
        // Keep the old status if it's further along than "not submitted"
        if existing.status != .notSubmitted && claim.status == .notSubmitted {
            claim.status = existing.status
            claim.statusHistory = existing.statusHistory
        }
        
        // Use the existing claim's ID so it's an in-place update
        claim.id = existing.id
        claim.createdAt = existing.createdAt  // preserve original creation date
        claim.updatedAt = Date()
        
        patientDataService.saveClaim(claim)
        savedClaimId = claim.id
        
        duplicateClaim = nil
        pendingClaim = nil
        pendingProviderId = nil
        isSaving = false
        saveResult = .scanMore
    }
    
    /// Keep both the existing and new claim
    private func saveAsNewClaim() {
        guard let claim = pendingClaim else { return }
        isSaving = true
        
        patientDataService.saveClaim(claim)
        savedClaimId = claim.id
        
        duplicateClaim = nil
        pendingClaim = nil
        pendingProviderId = nil
        isSaving = false
        saveResult = .scanMore
    }
    
    // MARK: - Insurance Policy Creation
    
    /// Find an existing policy or create a new one from scanned insurance data.
    /// Returns the policy ID, or nil if no insurance data was scanned.
    private func createOrFindInsurancePolicy(patientId: String) -> String? {
        // Need at least a carrier name or member ID to create a policy
        guard !insuranceCarrier.isEmpty || !memberId.isEmpty else { return nil }
        
        // ── Find or create carrier ──
        let carrierName = insuranceCarrier.trimmingCharacters(in: .whitespaces)
        var carrierId: String
        
        if !carrierName.isEmpty {
            // Try to match an existing carrier (case-insensitive, contains match)
            let carrierLower = carrierName.lowercased()
            if let existing = patientDataService.insuranceCarriers.first(where: {
                $0.name.lowercased() == carrierLower
                || $0.name.lowercased().contains(carrierLower)
                || carrierLower.contains($0.name.lowercased())
                || ($0.shortName?.lowercased() == carrierLower)
            }) {
                carrierId = existing.id
            } else {
                // Create new carrier
                let newCarrier = InsuranceCarrier(
                    name: carrierName,
                    phones: []
                )
                patientDataService.saveCarrier(newCarrier)
                carrierId = newCarrier.id
                #if DEBUG
                print("🏥 Created carrier from scan: \(carrierName) (id: \(carrierId))")
                #endif
            }
        } else {
            carrierId = "unknown"
        }
        
        // ── Find existing policy for this patient + carrier ──
        let existingPolicies = patientDataService.policies(for: patientId)
        
        // Match by member ID (strongest match)
        if !memberId.isEmpty {
            if let existing = existingPolicies.first(where: {
                $0.memberId.lowercased() == memberId.lowercased()
            }) {
                // Update existing policy with any new scanned data
                var updated = existing
                var changed = false
                if updated.groupNumber == nil && !groupNumber.isEmpty {
                    updated.groupNumber = groupNumber; changed = true
                }
                if updated.policyNumber == nil && !policyNumber.isEmpty {
                    updated.policyNumber = policyNumber; changed = true
                }
                if updated.planType == nil && !insurancePlanType.isEmpty {
                    if let pt = matchPlanType(insurancePlanType) {
                        updated.planType = pt; changed = true
                    }
                }
                if changed {
                    patientDataService.savePolicy(updated)
                }
                return existing.id
            }
        }
        
        // Match by policy number
        if !policyNumber.isEmpty {
            if let existing = existingPolicies.first(where: {
                $0.policyNumber?.lowercased() == policyNumber.lowercased()
            }) {
                return existing.id
            }
        }
        
        // Match by carrier (same carrier, only policy for this patient)
        if let existing = existingPolicies.first(where: { $0.carrierId == carrierId }) {
            // Update with any new data
            var updated = existing
            var changed = false
            if updated.memberId.isEmpty && !memberId.isEmpty {
                updated.memberId = memberId; changed = true
            }
            if updated.groupNumber == nil && !groupNumber.isEmpty {
                updated.groupNumber = groupNumber; changed = true
            }
            if updated.policyNumber == nil && !policyNumber.isEmpty {
                updated.policyNumber = policyNumber; changed = true
            }
            if changed {
                patientDataService.savePolicy(updated)
            }
            return existing.id
        }
        
        // ── Create new policy ──
        let policy = InsurancePolicy(
            patientId: patientId,
            carrierId: carrierId,
            policyType: .medical,
            planType: matchPlanType(insurancePlanType),
            planName: insurancePlanType.isEmpty ? nil : insurancePlanType,
            memberId: memberId,
            groupNumber: groupNumber.isEmpty ? nil : groupNumber,
            policyNumber: policyNumber.isEmpty ? nil : policyNumber,
            isPrimary: existingPolicies.isEmpty // Primary if it's the first policy
        )
        
        patientDataService.savePolicy(policy)
        
        // Link policy to patient
        if var patient = patientDataService.patients.first(where: { $0.id == patientId }) {
            if !patient.insurancePolicyIds.contains(policy.id) {
                patient.insurancePolicyIds.append(policy.id)
                patientDataService.savePatient(patient)
            }
        }
        
        #if DEBUG
        print("📋 Created insurance policy from scan: \(carrierName) memberId=\(memberId) policy=\(policyNumber) (id: \(policy.id))")
        #endif
        
        return policy.id
    }
    
    /// Match scanned plan type text to PlanType enum
    private func matchPlanType(_ text: String) -> PlanType? {
        let upper = text.uppercased()
        if upper.contains("HMO") { return .hmo }
        if upper.contains("PPO") { return .ppo }
        if upper.contains("EPO") { return .epo }
        if upper.contains("POS") { return .pos }
        if upper.contains("HDHP") || upper.contains("HIGH DEDUCTIBLE") { return .hdhp }
        if upper.contains("MEDICARE ADV") { return .medicareAdvantage }
        if upper.contains("MEDICARE SUP") || upper.contains("MEDIGAP") { return .medicareSupplement }
        if upper.contains("MEDICARE PART D") || upper.contains("PART D") { return .medicarePartD }
        if upper.contains("MEDICAID") { return .medicaid }
        if upper.contains("TRICARE") { return .tricare }
        return nil
    }
    
    // MARK: - Provider Creation with Geocoding
    
    /// Find existing provider by name or create a new one with address, phone, NPI.
    /// Geocodes the address and starts geofence monitoring.
    @MainActor
    private func createOrUpdateProvider() async -> String? {
        guard !providerName.isEmpty else { return nil }
        
        // Check if provider already exists (case-insensitive name match)
        if let existing = patientDataService.providers.first(where: {
            $0.name.lowercased() == providerName.lowercased()
        }) {
            // Update existing provider if we have new info it's missing
            var updated = existing
            var needsSave = false
            
            if updated.address == nil, let addr = parseAddressFields() {
                updated.address = addr
                needsSave = true
            }
            if updated.phones.isEmpty, !providerPhone.isEmpty {
                updated.phones = [PhoneNumber(label: .main, number: providerPhone, isPrimary: true)]
                needsSave = true
            }
            if updated.fax == nil, !providerFax.isEmpty {
                updated.fax = providerFax
                needsSave = true
            }
            if updated.emails.isEmpty, !providerEmail.isEmpty {
                updated.emails = [providerEmail]
                needsSave = true
            }
            if updated.website == nil, !providerWebsite.isEmpty {
                updated.website = providerWebsite
                needsSave = true
            }
            if updated.npi == nil, !providerNPI.isEmpty {
                updated.npi = providerNPI
                needsSave = true
            }
            if updated.taxId == nil, !providerTaxId.isEmpty {
                updated.taxId = providerTaxId
                needsSave = true
            }
            if updated.licenseNumber == nil, !providerLicense.isEmpty {
                updated.licenseNumber = providerLicense
                needsSave = true
            }
            
            // Geocode if address was added and no coordinates yet
            if needsSave && updated.address != nil && !updated.hasLocation {
                let _ = await LocationReminderService.shared.geocodeAndUpdateProvider(&updated)
                if updated.hasLocation && updated.isGeofenceActive {
                    LocationReminderService.shared.startMonitoringProvider(updated)
                }
            }
            
            if needsSave {
                updated.updatedAt = Date()
                patientDataService.saveProvider(updated)
            }
            
            return existing.id
        }
        
        // Create new provider
        let address = parseAddressFields()
        
        var phones: [PhoneNumber] = []
        if !providerPhone.isEmpty {
            phones.append(PhoneNumber(label: .main, number: providerPhone, isPrimary: true))
        }
        
        var emails: [String] = []
        if !providerEmail.isEmpty { emails.append(providerEmail) }
        
        var provider = Provider(
            name: providerName,
            providerType: guessProviderType(from: providerName),
            address: address,
            phones: phones,
            emails: emails,
            fax: providerFax.isEmpty ? nil : providerFax,
            website: providerWebsite.isEmpty ? nil : providerWebsite,
            npi: providerNPI.isEmpty ? nil : providerNPI,
            taxId: providerTaxId.isEmpty ? nil : providerTaxId,
            licenseNumber: providerLicense.isEmpty ? nil : providerLicense,
            isGeofenceActive: address != nil
        )
        
        // Geocode if we have an address
        if address != nil {
            let success = await LocationReminderService.shared.geocodeAndUpdateProvider(&provider)
            if success && provider.isGeofenceActive {
                LocationReminderService.shared.startMonitoringProvider(provider)
            }
            #if DEBUG
            print("── Provider geocode: \(success ? "✅" : "❌") \(provider.address?.latitude ?? 0), \(provider.address?.longitude ?? 0)")
            #endif
        }
        
        patientDataService.saveProvider(provider)
        return provider.id
    }
    
    // MARK: - Address Parsing
    
    /// Parse raw address text into structured Address fields.
    /// Handles formats like:
    ///   "4200 W. Colonial Drive, Orlando, FL 32811"
    ///   "4200 W Colonial Drive  Orlando, FL 32811"
    ///   Multi-line: "4200 W Colonial Drive\nOrlando, FL 32811"
    private func parseAddressFields() -> Address? {
        // Combine provider address into one line for parsing
        let raw = providerAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        
        // Normalize: replace newlines with commas
        let normalized = raw.replacingOccurrences(of: "\n", with: ", ")
            .replacingOccurrences(of: "  ", with: ", ")  // double-space from OCR column join
        
        // Try to find ZIP code (5 or 5+4 digits)
        let zipPattern = #"\b(\d{5})(-\d{4})?\b"#
        guard let zipRegex = try? NSRegularExpression(pattern: zipPattern),
              let zipMatch = zipRegex.firstMatch(in: normalized, range: NSRange(normalized.startIndex..., in: normalized)),
              let zipRange = Range(zipMatch.range, in: normalized) else {
            // No ZIP found — can't parse reliably, store as street1 only
            return Address(type: .work, street1: raw, city: "", state: "", zipCode: "", isPrimary: true)
        }
        
        let zipCode = String(normalized[zipRange])
        let beforeZip = String(normalized[normalized.startIndex..<zipRange.lowerBound])
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: ","))
            .trimmingCharacters(in: .whitespaces)
        
        // Try to find state abbreviation right before ZIP
        var state = ""
        var beforeState = beforeZip
        let stateAbbreviations = Set(USState.all.map { $0.abbreviation })
        
        // Check last 2 chars or last word before ZIP
        let words = beforeZip.components(separatedBy: CharacterSet(charactersIn: ", "))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        
        if let lastWord = words.last, stateAbbreviations.contains(lastWord.uppercased()) {
            state = lastWord.uppercased()
            // Remove state from beforeState
            if let stateRange = beforeZip.range(of: lastWord, options: .backwards) {
                beforeState = String(beforeZip[beforeZip.startIndex..<stateRange.lowerBound])
                    .trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: ","))
                    .trimmingCharacters(in: .whitespaces)
            }
        }
        
        // Split remaining into street and city
        // The last comma-separated segment is the city
        let parts = beforeState.components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        
        var street1 = ""
        var city = ""
        
        if parts.count >= 2 {
            city = parts.last ?? ""
            street1 = parts.dropLast().joined(separator: ", ")
        } else if parts.count == 1 {
            // Only one chunk — could be "4200 W Colonial Drive Orlando"
            // Try to split on the last word that looks like a city name (capitalized, no digits)
            let chunk = parts[0]
            // If it starts with a number, it likely has street + city together
            // Use last capitalized word group as city
            if chunk.first?.isNumber == true {
                // Find where city starts: after the last digit-containing word
                let chunkWords = chunk.split(separator: " ").map { String($0) }
                var lastDigitIdx = 0
                for (i, w) in chunkWords.enumerated() {
                    if w.rangeOfCharacter(from: .decimalDigits) != nil { lastDigitIdx = i }
                }
                // Everything after the street-like portion is the city
                if lastDigitIdx < chunkWords.count - 1 {
                    street1 = chunkWords[0...lastDigitIdx].joined(separator: " ")
                    city = chunkWords[(lastDigitIdx + 1)...].joined(separator: " ")
                } else {
                    street1 = chunk
                }
            } else {
                city = chunk
            }
        }
        
        guard !street1.isEmpty || !city.isEmpty else { return nil }
        
        #if DEBUG
        print("── Parsed address: street=\"\(street1)\" city=\"\(city)\" state=\"\(state)\" zip=\"\(zipCode)\"")
        #endif
        
        return Address(
            type: .work,
            street1: street1,
            city: city,
            state: state,
            zipCode: zipCode,
            isPrimary: true
        )
    }
    
    /// Guess provider type from name keywords
    private func guessProviderType(from name: String) -> ProviderType {
        let lower = name.lowercased()
        if lower.contains("hospital") { return .hospital }
        if lower.contains("emergency") || lower.contains("er ") { return .emergencyRoom }
        if lower.contains("urgent") { return .urgentCare }
        if lower.contains("pharmacy") || lower.contains("rx") { return .pharmacy }
        if lower.contains("lab") { return .laboratory }
        if lower.contains("imaging") || lower.contains("radiology") { return .imagingCenter }
        if lower.contains("dental") || lower.contains("dentist") { return .dentist }
        if lower.contains("eye") || lower.contains("vision") || lower.contains("optom") { return .optometrist }
        if lower.contains("clinic") || lower.contains("medical center") || lower.contains("health center") { return .clinic }
        if lower.contains("dr.") || lower.contains("dr ") || lower.contains("md") { return .doctor }
        return .clinic
    }
}

// MARK: - Line Item Row

struct LineItemRow: View {
    @Binding var item: ParsedLineItem
    @State private var amountText: String = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                // Selection toggle
                Button {
                    item.isSelected.toggle()
                } label: {
                    Image(systemName: item.isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(item.isSelected ? .accentColor : .secondary)
                }
                .buttonStyle(.plain)
                
                // Code + type badge
                if !item.code.isEmpty {
                    HStack(spacing: 4) {
                        if let codeType = item.codeType {
                            Text(codeType.rawValue)
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 4).padding(.vertical, 1)
                                .background(codeTypeColor(codeType))
                                .cornerRadius(3)
                        }
                        
                        Text(item.code)
                            .font(.system(.caption, design: .monospaced))
                            .fontWeight(.semibold)
                    }
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.1))
                    .cornerRadius(4)
                }
                
                Spacer()
                
                // Amount
                Text(item.amount, format: .currency(code: "USD"))
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(item.isSelected ? .primary : .secondary)
            }
            
            // Description (editable)
            TextField("Description", text: $item.description)
                .font(.caption)
                .foregroundColor(.secondary)
            
            // Database match info
            if let mc = item.matchedMedicalCode {
                // Show database description if different from displayed
                if mc.shortDescription.lowercased() != item.description.lowercased() {
                    Text(mc.shortDescription)
                        .font(.caption2)
                        .foregroundColor(Color("BrandCyan").opacity(0.7))
                        .lineLimit(2)
                }
                
                // Database price range
                if mc.hasValidPricing {
                    HStack(spacing: 4) {
                        Image(systemName: "chart.bar.fill")
                            .font(.system(size: 8))
                        Text("Typical: \(mc.formattedPriceRange)")
                            .font(.caption2)
                    }
                    .foregroundColor(.green)
                }
            } else if item.lookupFailed && !item.code.isEmpty {
                Text("Not in code database")
                    .font(.caption2)
                    .foregroundColor(.orange)
            }
        }
        .padding(.vertical, 2)
        .opacity(item.isSelected ? 1.0 : 0.5)
        .onAppear {
            amountText = String(format: "%.2f", item.amount)
        }
    }
    
    private func codeTypeColor(_ type: MedicalCodeType) -> Color {
        switch type {
        case .cpt: return Color("BrandCyan")
        case .icd10: return .green
        case .icd10pcs: return .teal
        case .hcpcs: return .orange
        }
    }
}

// MARK: - Camera View

struct CameraView: UIViewControllerRepresentable {
    @Binding var image: UIImage?
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
        let parent: CameraView
        
        init(_ parent: CameraView) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.image = image
            }
            parent.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

// MARK: - Image Picker (Photo Library)

struct ImagePicker: UIViewControllerRepresentable {
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
        let parent: ImagePicker
        
        init(_ parent: ImagePicker) {
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

// MARK: - Document Picker (Files)

struct DocumentPicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
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
        let parent: DocumentPicker
        
        init(_ parent: DocumentPicker) {
            self.parent = parent
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            
            // Start accessing security-scoped resource
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
                // Load image directly
                if let data = try? Data(contentsOf: url),
                   let image = UIImage(data: data) {
                    DispatchQueue.main.async {
                        self.parent.image = image
                    }
                }
            }
        }
        
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.dismiss()
        }
        
        private func pdfToImage(url: URL) -> UIImage? {
            guard let document = CGPDFDocument(url as CFURL),
                  let page = document.page(at: 1) else { return nil }
            
            let pageRect = page.getBoxRect(.mediaBox)
            let scale: CGFloat = 2.0  // Higher resolution
            
            let renderer = UIGraphicsImageRenderer(size: CGSize(
                width: pageRect.width * scale,
                height: pageRect.height * scale
            ))
            
            return renderer.image { context in
                UIColor.white.setFill()
                context.fill(CGRect(origin: .zero, size: renderer.format.bounds.size))
                
                context.cgContext.translateBy(x: 0, y: pageRect.height * scale)
                context.cgContext.scaleBy(x: scale, y: -scale)
                context.cgContext.drawPDFPage(page)
            }
        }
    }
}

#Preview {
    BillScannerView()
        .environmentObject(PatientDataService.shared)
        .environmentObject(AppState())
}
