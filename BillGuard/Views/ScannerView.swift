//
//  ScannerView.swift
//  BillGuard
//
//  Scan medical codes with adjustable region selection.
//  Uses a custom table-style resizable rectangle and column-aware
//  spatial OCR to detect code / description / price columns.
//

import SwiftUI
import Vision
import VisionKit

// MARK: - OCR Cell (text + bounding box)

/// A single text observation with its normalized position from Vision
struct OCRTextCell {
    let text: String
    let midX: CGFloat   // 0–1 horizontal center
    let midY: CGFloat   // 0–1 vertical center (Vision: 0 = bottom)
    let width: CGFloat
    let height: CGFloat
}

// MARK: - Parsed Table Row

struct ParsedBillRow {
    var code: String = ""
    var codeType: MedicalCodeType?
    var description: String = ""
    var amount: Double?
    var rawTexts: [String] = []
}

// MARK: - Extracted Bill Info (patient + provider fields)

struct ExtractedBillInfo: Codable {
    // Patient
    var patientName: String = ""
    var accountNumber: String = ""
    var patientAddress: String = ""
    var dateOfService: String = ""
    var dateOfBirth: String = ""
    
    // Provider
    var providerName: String = ""
    var providerAddress: String = ""
    var providerPhone: String = ""
    var providerFax: String = ""
    
    // Insurance
    var insuranceName: String = ""
    var policyNumber: String = ""
    var memberId: String = ""
    var groupNumber: String = ""
    var mrn: String = ""
    
    // Financial summary
    var totalCharges: String = ""
    var insuranceAdjustment: String = ""
    var insurancePaid: String = ""
    var amountDue: String = ""
    
    var hasPatientInfo: Bool {
        !patientName.isEmpty || !accountNumber.isEmpty || !patientAddress.isEmpty
    }
    var hasProviderInfo: Bool {
        !providerName.isEmpty || !providerAddress.isEmpty
    }
    var hasInsuranceInfo: Bool {
        !insuranceName.isEmpty || !policyNumber.isEmpty || !memberId.isEmpty
    }
    var hasFinancialInfo: Bool {
        !totalCharges.isEmpty || !amountDue.isEmpty
    }
    var hasAnyInfo: Bool {
        hasPatientInfo || hasProviderInfo || hasInsuranceInfo || hasFinancialInfo
    }
}

// MARK: - Saved Scan (for file export)

struct SavedScanCode: Codable {
    var code: String
    var codeType: String
    var description: String
    var scannedPrice: Double?
    var databaseDescription: String?
    var databasePriceRange: String?
}

struct SavedScan: Codable {
    var id: String
    var name: String                 // File-friendly name (from facility)
    var billInfo: ExtractedBillInfo
    var codes: [SavedScanCode]
    var scanDate: Date
    var imageFileName: String?       // Associated JPEG filename
    
    /// Generate a file-safe version of the name
    var safeFileName: String {
        let cleaned = name
            .components(separatedBy: CharacterSet.alphanumerics.union(.whitespaces).inverted)
            .joined()
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: " ", with: "_")
        return cleaned.isEmpty ? "Scan_\(id.prefix(8))" : cleaned
    }
}

// MARK: - ScannerView

struct ScannerView: View {
    
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var scannerVM: ScannerViewModel?
    
    // Image capture
    @State private var selectedImage: UIImage?
    @State private var showingCamera = false
    @State private var showingPhotoPicker = false
    @State private var showingFilePicker = false
    
    // Flow
    @State private var showingRegionSelector = false
    @State private var isProcessing = false
    @State private var showingResults = false
    
    // Table region — single resizable box
    @State private var tableRegion = TableSelectionRegion(
        center: CGPoint(x: 0.5, y: 0.5),
        size: CGSize(width: 0.92, height: 0.55)
    )
    
    // Image zoom & pan for region selector
    @State private var imageZoom: CGFloat = 1.0
    @State private var imageOffset: CGSize = .zero
    @GestureState private var pinchScale: CGFloat = 1.0
    @GestureState private var dragOffset: CGSize = .zero
    
    // Results
    @State private var extractedText = ""
    @State private var extractedCodes: [ScannedCode] = []
    @State private var selectedCodeIds: Set<UUID> = []
    @State private var selectedCode: MedicalCode?
    @State private var columnSummary = ""
    @State private var billInfo = ExtractedBillInfo()
    
    /// Optional dismiss closure for fullScreenCover
    var onDismiss: (() -> Void)? = nil
    
    /// Optional callback to export scanned codes to Bill Scanner
    var onImportCodes: (([ScannedCode]) -> Void)? = nil
    var addToDBMode: Bool = false
    @State private var showingAddToDatabase = false
    
    // Save scan
    @State private var showingSaveAlert = false
    @State private var saveScanName = ""
    @State private var showingSavedConfirmation = false
    @State private var savedFileName = ""
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if showingResults {
                    resultsView
                } else if isProcessing {
                    processingView
                } else if showingRegionSelector {
                    regionSelectorView
                } else {
                    sourceSelectionView
                }
            }
            .navigationTitle("Add New Codes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        if let onDismiss { onDismiss() } else { dismiss() }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundColor(.secondary)
                    }
                }
                if showingResults && (!extractedCodes.isEmpty || billInfo.hasAnyInfo) {
                    // "Add to Bill" stays in the nav bar (short label, fits fine)
                    if let importCodes = onImportCodes, !addToDBMode, !extractedCodes.isEmpty {
                        ToolbarItem(placement: .confirmationAction) {
                            Button {
                                importCodes(extractedCodes)
                                if let onDismiss { onDismiss() } else { dismiss() }
                            } label: {
                                Text("Add to Bill")
                                    .fontWeight(.semibold)
                                    .foregroundColor(Color("BrandCyan"))
                            }
                        }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Menu {
                            Button { promptSaveScan() } label: {
                                Label("Save Scan", systemImage: "square.and.arrow.down")
                            }
                            if !extractedCodes.isEmpty {
                                Divider()
                                Button { selectedCodeIds = Set(extractedCodes.map(\.id)) } label: {
                                    Label("Select All", systemImage: "checkmark.circle")
                                }
                                Button { selectedCodeIds.removeAll() } label: {
                                    Label("Deselect All", systemImage: "circle")
                                }
                            }
                            Divider()
                            Button(role: .destructive) { resetAll() } label: {
                                Label("Start Over", systemImage: "arrow.counterclockwise")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
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
            .sheet(isPresented: $showingAddToDatabase) {
                AddCodesToDatabaseView(
                    codes: extractedCodes.filter { selectedCodeIds.contains($0.id) }.isEmpty
                        ? extractedCodes
                        : extractedCodes.filter { selectedCodeIds.contains($0.id) }
                )
                .environmentObject(appState)
            }
            // "Add to Database" as a full-width bottom bar button in DB mode —
            // keeps the nav bar title unobstructed.
            .toolbar {
                if addToDBMode, showingResults, !extractedCodes.isEmpty {
                    ToolbarItem(placement: .bottomBar) {
                        Button {
                            showingAddToDatabase = true
                        } label: {
                            HStack {
                                Image(systemName: "externaldrive.badge.plus").font(.title3)
                                Text("Add \(selectedCodeIds.isEmpty ? extractedCodes.count : selectedCodeIds.count) Code\(selectedCodeIds.count == 1 ? "" : "s") to Database")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.yellow.opacity(0.9))
                            .foregroundColor(.black)
                            .cornerRadius(12)
                            .padding(.horizontal)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .alert("Save Scan", isPresented: $showingSaveAlert) {
                TextField("Scan name", text: $saveScanName)
                Button("Save") { saveScan() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Enter a name for this scan file.")
            }
            .overlay(alignment: .bottom) {
                if showingSavedConfirmation {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Saved as \"\(savedFileName)\"")
                            .font(.subheadline).fontWeight(.medium)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.ultraThinMaterial).cornerRadius(20)
                    .shadow(radius: 6)
                    .padding(.bottom, 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .navigationDestination(item: $selectedCode) { code in
                CodeDetailView(code: code).environmentObject(appState)
            }
            .onChange(of: selectedImage) { _, img in
                if img != nil { showingRegionSelector = true }
            }
            .onAppear {
                if scannerVM == nil {
                    scannerVM = ScannerViewModel(cloudKitService: appState.cloudKitService)
                }
            }
        }
    }
    
    // ─────────────────────────────────────────────
    // MARK: - Source Selection
    // ─────────────────────────────────────────────
    
    private var sourceSelectionView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.accentColor.opacity(0.08))
                    .frame(width: 130, height: 130)
                VStack(spacing: 6) {
                    Image(systemName: "tablecells")
                        .font(.system(size: 44)).foregroundColor(.accentColor)
                    Image(systemName: "viewfinder")
                        .font(.system(size: 20)).foregroundColor(.accentColor.opacity(0.6))
                }
            }
            
            // Yellow purpose-warning banner
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.yellow)
                    .font(.subheadline)
                Text("This is to add codes and descriptions to the database")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.black)
                Spacer()
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Color.yellow.opacity(0.85))
            .cornerRadius(10)
            .padding(.horizontal)

            VStack(spacing: 8) {
                Text("Add New Codes")
                    .font(.title2).fontWeight(.bold)
                Text("Capture new codes, then place the rectangle\nover the table with codes and prices")
                    .font(.subheadline).foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            VStack(alignment: .leading, spacing: 10) {
                Label("Place rectangle over the codes table", systemImage: "1.circle.fill")
                    .font(.subheadline)
                Label("Codes and descriptions are extracted automatically", systemImage: "2.circle.fill")
                    .font(.subheadline)
                Label("Review, select, and add new codes to the database", systemImage: "3.circle.fill")
                    .font(.subheadline)
            }
            .padding()
            .background(Color(.tertiarySystemBackground))
            .cornerRadius(12)
            .padding(.horizontal)
            
            VStack(spacing: 12) {
                Button { showingCamera = true } label: {
                    sourceRow(icon: "camera.fill", title: "Take Photo", primary: true)
                }
                Button { showingPhotoPicker = true } label: {
                    sourceRow(icon: "photo.on.rectangle", title: "Photo Library", primary: false)
                }
                Button { showingFilePicker = true } label: {
                    sourceRow(icon: "folder.fill", title: "Import PDF or Image", primary: false)
                }
            }
            .padding(.horizontal)
            
            Spacer()
            
            if let vm = scannerVM, !vm.scannedCodes.isEmpty {
                Button {
                    extractedCodes = vm.scannedCodes
                    if addToDBMode {
                        let dbSet = Set(appState.cloudKitService.allCodes.map { $0.code.uppercased() })
                        selectedCodeIds = Set(vm.scannedCodes.compactMap { code in
                            dbSet.contains(code.detectedCode.uppercased()) ? nil : code.id
                        })
                    } else {
                        selectedCodeIds = Set(vm.scannedCodes.map(\.id))
                    }
                    showingResults = true
                } label: {
                    HStack {
                        Image(systemName: "clock.arrow.circlepath")
                        Text("View \(vm.scannedCodes.count) Previous Code\(vm.scannedCodes.count == 1 ? "" : "s")")
                    }
                    .font(.subheadline).padding()
                    .frame(maxWidth: .infinity)
                    .background(Color(.tertiarySystemBackground)).cornerRadius(10)
                }
                .padding(.horizontal).padding(.bottom, 8)
            }
        }
    }
    
    private func sourceRow(icon: String, title: String, primary: Bool) -> some View {
        HStack {
            Image(systemName: icon).font(.title3).frame(width: 30)
            Text(title).fontWeight(.semibold)
            Spacer()
            Image(systemName: "chevron.right").foregroundColor(primary ? .white : .secondary)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(primary ? Color.accentColor : Color("BrandNavy"))
        .foregroundColor(primary ? .white : .primary)
        .cornerRadius(12)
    }
    
    // ─────────────────────────────────────────────
    // MARK: - Region Selector
    // ─────────────────────────────────────────────
    
    private var regionSelectorView: some View {
        VStack(spacing: 0) {
            // Instruction bar
            HStack(spacing: 8) {
                Image(systemName: "tablecells.badge.ellipsis").foregroundColor(.accentColor)
                Text("Drag rectangle over table area")
                    .font(.caption).foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal).padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(Color("BrandNavy"))
            
            // Image + rectangle — no zoom, 1:1 mapping to image coordinates
            GeometryReader { geo in
                if let image = selectedImage {
                    let baseFrame = fitImageFrame(image: image, in: geo.size)
                    
                    ZStack {
                        // Image at 1x
                        Image(uiImage: image)
                            .resizable().scaledToFit()
                            .frame(width: baseFrame.width, height: baseFrame.height)
                            .position(x: baseFrame.midX, y: baseFrame.midY)
                        
                        // Dim overlay
                        TableRegionDimOverlay(
                            region: tableRegion,
                            containerSize: CGSize(width: baseFrame.width, height: baseFrame.height),
                            offset: CGPoint(x: baseFrame.minX, y: baseFrame.minY)
                        )
                        
                        // Draggable rectangle
                        TableDraggableRect(
                            region: $tableRegion,
                            containerSize: CGSize(width: baseFrame.width, height: baseFrame.height),
                            offset: CGPoint(x: baseFrame.minX, y: baseFrame.minY)
                        )
                    }
                    .clipped()
                    .contentShape(Rectangle())
                }
            }
            
            // Bottom controls
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    ForEach(["Narrow", "Medium", "Large", "Full"], id: \.self) { preset in
                        Button(preset) {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                switch preset {
                                case "Narrow":  tableRegion = .init(center: .init(x: 0.5, y: 0.5), size: .init(width: 0.92, height: 0.22))
                                case "Medium":  tableRegion = .init(center: .init(x: 0.5, y: 0.5), size: .init(width: 0.92, height: 0.42))
                                case "Large":   tableRegion = .init(center: .init(x: 0.5, y: 0.5), size: .init(width: 0.95, height: 0.65))
                                default:        tableRegion = .init(center: .init(x: 0.5, y: 0.5), size: .init(width: 1.0, height: 1.0))
                                }
                            }
                        }
                        .buttonStyle(.bordered).tint(.accentColor).font(.caption)
                    }
                }
                
                HStack(spacing: 12) {
                    Button {
                        showingRegionSelector = false; selectedImage = nil
                    } label: {
                        HStack { Image(systemName: "arrow.counterclockwise"); Text("Retake") }
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(Color("BrandNavy"))
                            .foregroundColor(.primary).cornerRadius(10)
                    }
                    Button { processTableRegion() } label: {
                        HStack { Image(systemName: "tablecells.badge.ellipsis"); Text("Extract Table") }
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(Color.accentColor)
                            .foregroundColor(.white).cornerRadius(10)
                    }
                }
            }
            .padding().background(Color("BrandDeepNavy"))
        }
    }
    
    /// Current effective zoom level
    private var currentZoom: CGFloat { imageZoom * pinchScale }
    
    /// Current effective pan offset
    private var effectiveOffset: CGSize {
        CGSize(width: imageOffset.width + dragOffset.width,
               height: imageOffset.height + dragOffset.height)
    }
    
    /// Clamp pan offset so the image doesn't drift off-screen
    private func clampOffset(containerSize: CGSize) {
        let maxX = containerSize.width * (imageZoom - 1) / 2
        let maxY = containerSize.height * (imageZoom - 1) / 2
        imageOffset.width  = imageOffset.width.clamped(to: -maxX...maxX)
        imageOffset.height = imageOffset.height.clamped(to: -maxY...maxY)
    }
    
    // ─────────────────────────────────────────────
    // MARK: - Processing
    // ─────────────────────────────────────────────
    
    private var processingView: some View {
        VStack(spacing: 24) {
            Spacer()
            if let image = selectedImage {
                Image(uiImage: image).resizable().scaledToFit()
                    .frame(maxHeight: 180).cornerRadius(12).shadow(radius: 5)
            }
            ProgressView().scaleEffect(1.5).tint(.accentColor)
            VStack(spacing: 8) {
                Text("Analyzing Table…").font(.headline)
                Text("Detecting columns: codes · descriptions · prices")
                    .font(.caption).foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding()
    }
    
    // ─────────────────────────────────────────────
    // MARK: - Results
    // ─────────────────────────────────────────────
    
    private var resultsView: some View {
        VStack(spacing: 0) {
            if extractedCodes.isEmpty && !billInfo.hasAnyInfo { emptyResultsView }
            else { populatedResultsView }
        }
    }
    
    private var emptyResultsView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "doc.text.magnifyingglass").font(.system(size: 50)).foregroundColor(.secondary)
            Text("No medical codes found").font(.headline)
            Text("Try adjusting the rectangle to cover\nthe rows with codes and prices")
                .font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center)
            if !columnSummary.isEmpty {
                ScrollView {
                    Text(columnSummary).font(.system(.caption2, design: .monospaced)).foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 200).padding(8)
                .background(Color("BrandNavy")).cornerRadius(6)
            }
            if !extractedText.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Raw OCR text:").font(.caption).foregroundColor(.secondary)
                    ScrollView {
                        Text(extractedText).font(.caption2).foregroundColor(.secondary)
                    }
                    .frame(maxHeight: 120).padding(8)
                    .background(Color("BrandNavy")).cornerRadius(8)
                }
                .padding(.horizontal)
            }
            HStack(spacing: 12) {
                Button("Adjust Region") { goBackToRegion() }
                    .buttonStyle(.borderedProminent).tint(.blue)
                Button("New Image") { resetAll() }
                    .buttonStyle(.borderedProminent).tint(.accentColor)
            }
            Spacer()
        }
        .padding()
    }
    
    private var populatedResultsView: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 6) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        if extractedCodes.isEmpty {
                            Text("Bill info extracted")
                                .font(.subheadline).fontWeight(.medium)
                        } else {
                            Text("\(extractedCodes.count) code\(extractedCodes.count == 1 ? "" : "s") extracted")
                                .font(.subheadline).fontWeight(.medium)
                        }
                    }
                    Spacer()
                    if !extractedCodes.isEmpty {
                        Text("\(selectedCodeIds.count) selected")
                            .font(.caption).foregroundColor(.accentColor)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color.accentColor.opacity(0.1)).cornerRadius(8)
                    }
                }
                HStack(spacing: 12) {
                    if !extractedCodes.isEmpty {
                        Button {
                            if selectedCodeIds.count == extractedCodes.count { selectedCodeIds.removeAll() }
                            else { selectedCodeIds = Set(extractedCodes.map(\.id)) }
                        } label: {
                            Text(selectedCodeIds.count == extractedCodes.count ? "Deselect All" : "Select All").font(.caption)
                        }
                    }
                    Spacer()
                    Button { promptSaveScan() } label: { Label("Save", systemImage: "square.and.arrow.down").font(.caption) }
                    Button { goBackToRegion() } label: { Label("Adjust", systemImage: "crop").font(.caption) }
                    Button { resetAll() } label: { Label("New", systemImage: "camera").font(.caption) }
                }
            }
            .padding(.horizontal).padding(.vertical, 10)
            .background(Color("BrandNavy"))
            
            List {
                // Bill Info Sections — hidden in addToDBMode (irrelevant for code lookup)
                if billInfo.hasProviderInfo && !addToDBMode {
                    Section {
                        editableField("Facility/Provider", $billInfo.providerName, icon: "building.2")
                        if !billInfo.providerAddress.isEmpty {
                            editableField("Address", $billInfo.providerAddress, icon: "mappin.circle")
                        }
                        if !billInfo.providerPhone.isEmpty {
                            editableField("Phone", $billInfo.providerPhone, icon: "phone")
                        }
                        if !billInfo.providerFax.isEmpty {
                            editableField("Fax", $billInfo.providerFax, icon: "printer")
                        }
                    } header: {
                        Label("Provider", systemImage: "building.2.fill")
                    }
                }
                
                if billInfo.hasPatientInfo && !addToDBMode {
                    Section {
                        editableField("Patient Name", $billInfo.patientName, icon: "person")
                        if !billInfo.accountNumber.isEmpty {
                            editableField("Account #", $billInfo.accountNumber, icon: "number")
                        }
                        if !billInfo.patientAddress.isEmpty {
                            editableField("Address", $billInfo.patientAddress, icon: "mappin.circle")
                        }
                        if !billInfo.dateOfService.isEmpty {
                            editableField("Date of Service", $billInfo.dateOfService, icon: "calendar")
                        }
                        if !billInfo.dateOfBirth.isEmpty {
                            editableField("Date of Birth", $billInfo.dateOfBirth, icon: "calendar.badge.clock")
                        }
                        if !billInfo.mrn.isEmpty {
                            editableField("MRN", $billInfo.mrn, icon: "doc.text")
                        }
                    } header: {
                        Label("Patient", systemImage: "person.fill")
                    }
                }
                
                if billInfo.hasInsuranceInfo && !addToDBMode {
                    Section {
                        if !billInfo.insuranceName.isEmpty {
                            editableField("Insurance", $billInfo.insuranceName, icon: "shield")
                        }
                        if !billInfo.policyNumber.isEmpty {
                            editableField("Policy #", $billInfo.policyNumber, icon: "number")
                        }
                        if !billInfo.memberId.isEmpty {
                            editableField("Member ID", $billInfo.memberId, icon: "person.badge.key")
                        }
                        if !billInfo.groupNumber.isEmpty {
                            editableField("Group #", $billInfo.groupNumber, icon: "person.3")
                        }
                    } header: {
                        Label("Insurance", systemImage: "shield.fill")
                    }
                }
                
                // Codes section
                if !extractedCodes.isEmpty {
                    Section {
                        ForEach(extractedCodes) { code in
                            if addToDBMode {
                                // Three-state badge: New / User / In DB
                                let up = code.detectedCode.uppercased()
                                let isBuiltIn = appState.cloudKitService.allCodes
                                    .contains(where: { $0.code.uppercased() == up })
                                let isUserAdded: Bool = {
                                    guard !isBuiltIn,
                                          let data = UserDefaults.standard.data(forKey: "UserAddedMedicalCodes_v1"),
                                          let custom = try? JSONDecoder().decode([CustomMedicalCode].self, from: data)
                                    else { return false }
                                    return custom.contains(where: { $0.code.uppercased() == up })
                                }()

                                HStack(spacing: 0) {
                                    ScanCodeResultRow(
                                        code: code,
                                        isSelected: selectedCodeIds.contains(code.id),
                                        onToggle: { toggleCode(code.id) },
                                        onTap: { if let m = code.matchedMedicalCode { selectedCode = m } }
                                    )
                                    Spacer(minLength: 6)
                                    Group {
                                        if isBuiltIn {
                                            Text("In DB")
                                                .foregroundColor(.secondary)
                                                .background(Color(.tertiarySystemBackground))
                                        } else if isUserAdded {
                                            Text("User")
                                                .foregroundColor(.white)
                                                .background(Color.blue.opacity(0.75))
                                        } else {
                                            Text("New")
                                                .foregroundColor(.black)
                                                .background(Color.yellow.opacity(0.9))
                                        }
                                    }
                                    .font(.caption2).fontWeight(.semibold)
                                    .padding(.horizontal, 7).padding(.vertical, 3)
                                    .cornerRadius(6)
                                }
                            } else {
                                ScanCodeResultRow(
                                    code: code,
                                    isSelected: selectedCodeIds.contains(code.id),
                                    onToggle: { toggleCode(code.id) },
                                    onTap: { if let m = code.matchedMedicalCode { selectedCode = m } }
                                )
                            }
                        }
                        .onDelete { offsets in
                            let ids = offsets.map { extractedCodes[$0].id }
                            extractedCodes.remove(atOffsets: offsets)
                            for id in ids { selectedCodeIds.remove(id) }
                        }
                    } header: {
                        if addToDBMode {
                            HStack {
                                Label("Scanned Codes", systemImage: "barcode.viewfinder")
                                Spacer()
                                HStack(spacing: 5) {
                                    Text("New").font(.caption2).fontWeight(.semibold).foregroundColor(.black)
                                        .padding(.horizontal, 5).padding(.vertical, 2)
                                        .background(Color.yellow.opacity(0.9)).cornerRadius(4)
                                    Text("User").font(.caption2).fontWeight(.semibold).foregroundColor(.white)
                                        .padding(.horizontal, 5).padding(.vertical, 2)
                                        .background(Color.blue.opacity(0.75)).cornerRadius(4)
                                    Text("In DB").font(.caption2).foregroundColor(.secondary)
                                        .padding(.horizontal, 5).padding(.vertical, 2)
                                        .background(Color(.tertiarySystemBackground)).cornerRadius(4)
                                }
                            }
                        } else {
                            Label("Medical Codes", systemImage: "barcode.viewfinder")
                        }
                    }
                }
                
                // Financial summary — hidden in addToDBMode
                if billInfo.hasFinancialInfo && !addToDBMode {
                    Section {
                        if !billInfo.totalCharges.isEmpty {
                            editableField("Total Charges", $billInfo.totalCharges, icon: "dollarsign.circle")
                        }
                        if !billInfo.insuranceAdjustment.isEmpty {
                            editableField("Insurance Adj.", $billInfo.insuranceAdjustment, icon: "arrow.down.circle")
                        }
                        if !billInfo.insurancePaid.isEmpty {
                            editableField("Insurance Paid", $billInfo.insurancePaid, icon: "checkmark.circle")
                        }
                        if !billInfo.amountDue.isEmpty {
                            editableField("Amount Due", $billInfo.amountDue, icon: "exclamationmark.circle")
                        }
                    } header: {
                        Label("Financial Summary", systemImage: "dollarsign.circle.fill")
                    }
                }
                
                if extractedCodes.contains(where: { $0.scannedPrice != nil }) && !addToDBMode {
                    Section("Scanned Totals") {
                        let allTotal = extractedCodes.compactMap(\.scannedPrice).reduce(0, +)
                        let selTotal = extractedCodes.filter { selectedCodeIds.contains($0.id) }
                            .compactMap(\.scannedPrice).reduce(0, +)
                        HStack { Text("All Codes Total"); Spacer(); Text(allTotal, format: .currency(code: "USD")).foregroundColor(.secondary) }
                        if selectedCodeIds.count != extractedCodes.count {
                            HStack { Text("Selected Total").fontWeight(.medium); Spacer()
                                Text(selTotal, format: .currency(code: "USD")).fontWeight(.semibold).foregroundColor(.accentColor)
                            }
                        }
                    }
                }
                
                if extractedCodes.contains(where: { $0.matchedMedicalCode?.hasValidPricing == true }) && !addToDBMode {
                    Section("Database Price Comparison") {
                        ForEach(extractedCodes.filter { $0.matchedMedicalCode?.hasValidPricing == true }) { code in
                            if let matched = code.matchedMedicalCode {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(code.detectedCode).font(.system(.caption, design: .monospaced)).fontWeight(.semibold)
                                        Text(matched.formattedPriceRange).font(.caption2).foregroundColor(.green)
                                    }
                                    Spacer()
                                    if let scanned = code.scannedPrice {
                                        let avg = matched.priceAverage ?? 0; let diff = scanned - avg
                                        VStack(alignment: .trailing, spacing: 2) {
                                            Text("Billed: \(scanned, format: .currency(code: "USD"))").font(.caption)
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
            }
            .listStyle(.insetGrouped)
        }
    }
    
    @ViewBuilder
    private func editableField(_ label: String, _ value: Binding<String>, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(.accentColor)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.caption).foregroundColor(.secondary)
                TextField(label, text: value)
                    .font(.subheadline)
            }
        }
    }
    
    private func toggleCode(_ id: UUID) {
        if selectedCodeIds.contains(id) { selectedCodeIds.remove(id) }
        else { selectedCodeIds.insert(id) }
    }
    
    // ─────────────────────────────────────────────
    // MARK: - Image Helpers
    // ─────────────────────────────────────────────
    
    private func fitImageFrame(image: UIImage, in container: CGSize) -> CGRect {
        let ia = image.size.width / image.size.height
        let ca = container.width / container.height
        let size: CGSize = ia > ca
            ? CGSize(width: container.width, height: container.width / ia)
            : CGSize(width: container.height * ia, height: container.height)
        return CGRect(
            x: (container.width - size.width) / 2,
            y: (container.height - size.height) / 2,
            width: size.width, height: size.height
        )
    }
    
    private func cropToRegion(_ image: UIImage, _ region: TableSelectionRegion) -> UIImage? {
        // Normalize orientation using pure CoreGraphics (thread-safe)
        let normalized = DocumentImageEnhancer.normalizeOrientation(image) ?? image.cgImage
        guard let cg = normalized else { return nil }
        
        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        let x = max(0, (region.center.x - region.size.width / 2)) * w
        let y = max(0, (region.center.y - region.size.height / 2)) * h
        let cw = min(region.size.width * w, w - x)
        let ch = min(region.size.height * h, h - y)
        guard cw > 10 && ch > 10 else { return nil }
        guard let cropped = cg.cropping(to: CGRect(x: x, y: y, width: cw, height: ch)) else { return nil }
        return UIImage(cgImage: cropped)
    }
    
    // ─────────────────────────────────────────────
    // MARK: - Process Table Region
    // ─────────────────────────────────────────────
    
    private func processTableRegion() {
        guard let image = selectedImage else { return }
        showingRegionSelector = false
        isProcessing = true
        
        // Debug
        let imgW = image.size.width, imgH = image.size.height
        let cgW = CGFloat(image.cgImage?.width ?? 0), cgH = CGFloat(image.cgImage?.height ?? 0)
        let ori = image.imageOrientation.rawValue
        let cropDebug = String(format: "Rgn: cx%.2f cy%.2f w%.2f h%.2f\nImg: %.0f×%.0f CG: %.0f×%.0f ori:%d",
            tableRegion.center.x, tableRegion.center.y,
            tableRegion.size.width, tableRegion.size.height,
            imgW, imgH, cgW, cgH, ori)
        
        let cropped = cropToRegion(image, tableRegion) ?? image
        
        Task {
            do {
                // Run table OCR and full-bill info extraction in parallel
                async let tableResult = recognizeWithPositions(cropped)
                async let infoResult = extractBillInfo(from: image)
                
                let (cells, rawText) = try await tableResult
                let extractedInfo = await infoResult
                let (codes, info) = buildCodesFromColumns(cells: cells)
                
                await MainActor.run {
                    extractedText = rawText
                    extractedCodes = codes
                    // In addToDBMode: only pre-select codes NOT already in the database.
                    // Codes that are "In DB" are deselected by default so the user
                    // doesn't accidentally try to add duplicates.
                    if addToDBMode {
                        let dbCodes = Set(appState.cloudKitService.allCodes.map { $0.code.uppercased() })
                        let userCodes: Set<String>
                        if let data = UserDefaults.standard.data(forKey: "UserAddedMedicalCodes_v1"),
                           let custom = try? JSONDecoder().decode([CustomMedicalCode].self, from: data) {
                            userCodes = Set(custom.map { $0.code.uppercased() })
                        } else {
                            userCodes = []
                        }
                        selectedCodeIds = Set(codes.compactMap { code in
                            let up = code.detectedCode.uppercased()
                            return (dbCodes.contains(up) || userCodes.contains(up)) ? nil : code.id
                        })
                    } else {
                        selectedCodeIds = Set(codes.map(\.id))
                    }
                    columnSummary = cropDebug + "\n" + info
                    billInfo = extractedInfo
                    isProcessing = false
                    showingResults = true

                    if let vm = scannerVM {
                        for code in codes where !vm.scannedCodes.contains(where: { $0.detectedCode == code.detectedCode }) {
                            vm.scannedCodes.insert(code, at: 0)
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    extractedText = "Error: \(error.localizedDescription)"
                    extractedCodes = []; columnSummary = cropDebug
                    billInfo = ExtractedBillInfo()
                    isProcessing = false; showingResults = true
                }
            }
        }
    }
    
    // ─────────────────────────────────────────────
    // MARK: - Vision OCR with Bounding Boxes
    // ─────────────────────────────────────────────
    
    private func recognizeWithPositions(_ image: UIImage) async throws -> ([OCRTextCell], String) {
        guard let cg = image.cgImage else {
            throw NSError(domain: "Scanner", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid image"])
        }
        return try await withCheckedThrowingContinuation { cont in
            let req = VNRecognizeTextRequest { req, err in
                if let err { cont.resume(throwing: err); return }
                guard let obs = req.results as? [VNRecognizedTextObservation] else {
                    cont.resume(returning: ([], "")); return
                }
                var cells: [OCRTextCell] = []
                var lines: [String] = []
                for o in obs {
                    guard let c = o.topCandidates(1).first else { continue }
                    let b = o.boundingBox
                    cells.append(OCRTextCell(text: c.string, midX: b.midX, midY: b.midY, width: b.width, height: b.height))
                    lines.append(c.string)
                }
                cont.resume(returning: (cells, lines.joined(separator: "\n")))
            }
            req.recognitionLevel = .accurate
            req.usesLanguageCorrection = true
            let handler = VNImageRequestHandler(cgImage: cg, options: [:])
            do { try handler.perform([req]) }
            catch { cont.resume(throwing: error) }
        }
    }
    
    
    // ─────────────────────────────────────────────
    // MARK: - Full Bill Info Extraction
    // ─────────────────────────────────────────────
    
    /// Run full-image OCR and extract patient, provider, insurance, and financial fields
    private func extractBillInfo(from image: UIImage) async -> ExtractedBillInfo {
        guard let cg = image.cgImage else { return ExtractedBillInfo() }
        
        // Run OCR on full image — group observations into rows by Y proximity
        // so two-column layouts like "Patient: John    Insurance: Aetna" become one line
        let lines: [String] = await withCheckedContinuation { cont in
            let req = VNRecognizeTextRequest { req, _ in
                guard let obs = req.results as? [VNRecognizedTextObservation] else {
                    cont.resume(returning: []); return
                }
                
                // Each observation has a bounding box in normalized coords (0-1, Y-up)
                struct TextBlock {
                    let text: String
                    let midX: CGFloat
                    let midY: CGFloat
                    let height: CGFloat
                }
                
                let blocks: [TextBlock] = obs.compactMap { o in
                    guard let text = o.topCandidates(1).first?.string else { return nil }
                    return TextBlock(text: text, midX: o.boundingBox.midX,
                                     midY: o.boundingBox.midY, height: o.boundingBox.height)
                }
                
                #if DEBUG
                print("── OCR blocks: \(blocks.count) ──")
                for b in blocks.sorted(by: { $0.midY > $1.midY }) {
                    print("  BLOCK midY=\(String(format: "%.4f", b.midY)) midX=\(String(format: "%.4f", b.midX)) h=\(String(format: "%.4f", b.height)): \"\(b.text)\"")
                }
                #endif
                
                // Group into rows: blocks within yTolerance of each other are the same row
                // Use the row anchor's midY; tolerance based on typical line height
                // Medical bills often have labels and values at slightly different Y baselines,
                // so use a generous tolerance (full line height or minimum 0.012)
                var rows: [[TextBlock]] = []
                let sorted = blocks.sorted { $0.midY > $1.midY } // top to bottom (Vision Y is bottom-up)
                
                for block in sorted {
                    let yTol = max(block.height * 1.0, 0.012) // full line height or minimum
                    if let rowIdx = rows.firstIndex(where: { row in
                        // Compare against the row's average midY for better grouping
                        let avgY = row.map { $0.midY }.reduce(0, +) / CGFloat(row.count)
                        return abs(avgY - block.midY) < yTol
                    }) {
                        rows[rowIdx].append(block)
                    } else {
                        rows.append([block])
                    }
                }
                
                // Sort rows top-to-bottom (by average Y), then sort blocks within each row left-to-right
                rows.sort {
                    let avgY0 = $0.map { $0.midY }.reduce(0, +) / CGFloat($0.count)
                    let avgY1 = $1.map { $0.midY }.reduce(0, +) / CGFloat($1.count)
                    return avgY0 > avgY1
                }
                let lines = rows.map { row in
                    row.sorted { $0.midX < $1.midX }
                       .map { $0.text }
                       .joined(separator: "  ")  // double space between columns
                }
                
                cont.resume(returning: lines)
            }
            req.recognitionLevel = .accurate
            req.usesLanguageCorrection = true
            let handler = VNImageRequestHandler(cgImage: cg, options: [:])
            try? handler.perform([req])
        }
        
        #if DEBUG
        print("── extractBillInfo: \(lines.count) OCR lines ──")
        for (i, line) in lines.enumerated() {
            print("  LINE[\(i)]: \(line)")
        }
        #endif
        
        var info = ExtractedBillInfo()
        
        // ── Pre-defined labels we recognize (used for multi-label line splitting) ──
        let recognizedLabels: [(pattern: String, key: String)] = [
            ("patient name", "patient name"),
            ("patient", "patient"),
            ("name", "name"),
            ("insured name", "insured name"),
            ("insured", "insured"),
            ("subscriber", "subscriber"),
            ("account #", "account #"),
            ("account no", "account no"),
            ("account number", "account number"),
            ("account", "account"),
            ("acct #", "acct #"),
            ("acct", "acct"),
            ("date of service", "date of service"),
            ("date(s) of service", "date of service"),
            ("service date", "service date"),
            ("dos", "dos"),
            ("date of birth", "date of birth"),
            ("dob", "dob"),
            ("mrn", "mrn"),
            ("medical record number", "mrn"),
            ("medical record", "mrn"),
            ("insurance company", "insurance"),
            ("insurance", "insurance"),
            ("carrier", "carrier"),
            ("payer", "payer"),
            ("policy #", "policy #"),
            ("policy no", "policy no"),
            ("policy number", "policy number"),
            ("policy", "policy"),
            ("member id", "member id"),
            ("member #", "member #"),
            ("member", "member"),
            ("subscriber id", "subscriber id"),
            ("group #", "group #"),
            ("group no", "group no"),
            ("group number", "group number"),
            ("group", "group"),
            ("provider", "provider"),
            ("facility", "facility"),
            ("hospital", "hospital"),
            ("clinic", "clinic"),
            ("phone", "phone"),
            ("tel", "tel"),
            ("telephone", "telephone"),
            ("fax", "fax"),
            ("total charges", "total charges"),
            ("amount due", "amount due"),
            ("balance due", "balance due"),
            ("patient balance", "patient balance"),
            ("total due", "total due"),
            ("insurance paid", "insurance paid"),
            ("ins paid", "ins paid"),
            ("insurance adjustment", "insurance adjustment"),
            ("ins adjustment", "ins adjustment"),
            ("ins. paid", "ins paid"),
            ("ins. adjustment", "ins adjustment"),
        ]
        
        /// Split a line that may contain multiple "Label: Value" pairs
        /// e.g. "Patient: Michael R. Thompson Insurance: Aetna PPO"
        /// → [("patient", "Michael R. Thompson"), ("insurance", "Aetna PPO")]
        func splitMultiLabelLine(_ line: String) -> [(String, String)] {
            let lower = line.lowercased()
            
            // Find all recognized label positions in the line
            var labelPositions: [(pos: Int, len: Int, key: String)] = []
            
            for (pattern, key) in recognizedLabels {
                var searchStart = lower.startIndex
                while let range = lower.range(of: pattern + ":", range: searchStart..<lower.endIndex) {
                    let pos = lower.distance(from: lower.startIndex, to: range.lowerBound)
                    let len = pattern.count + 1 // +1 for the ":"
                    // Don't add if it overlaps with an already-found longer label at same position
                    if !labelPositions.contains(where: { $0.pos == pos && $0.len >= len }) {
                        // Remove shorter matches at same position
                        labelPositions.removeAll { $0.pos == pos && $0.len < len }
                        labelPositions.append((pos, len, key))
                    }
                    searchStart = range.upperBound
                }
            }
            
            // Also find generic "Word: " patterns not in our list
            // (e.g. "ID:" or custom labels)
            if labelPositions.isEmpty {
                // Fall back to first-colon split
                if let colonRange = line.range(of: ":") {
                    let label = String(line[line.startIndex..<colonRange.lowerBound]).trimmingCharacters(in: .whitespaces)
                    let value = String(line[colonRange.upperBound...]).trimmingCharacters(in: .whitespaces)
                    if !label.isEmpty && label.count <= 30 {
                        return [(label.lowercased(), value)]
                    }
                }
                return []
            }
            
            // Sort by position
            labelPositions.sort { $0.pos < $1.pos }
            
            // Extract pairs
            var pairs: [(String, String)] = []
            for (idx, lp) in labelPositions.enumerated() {
                let valueStart = line.index(line.startIndex, offsetBy: lp.pos + lp.len)
                let valueEnd: String.Index
                if idx + 1 < labelPositions.count {
                    valueEnd = line.index(line.startIndex, offsetBy: labelPositions[idx + 1].pos)
                } else {
                    valueEnd = line.endIndex
                }
                let value = String(line[valueStart..<valueEnd]).trimmingCharacters(in: .whitespaces)
                pairs.append((lp.key, value))
            }
            
            return pairs
        }
        
        // ── Build pairs from OCR lines ──
        var pairs: [(String, String)] = []
        var skipNextLine: Set<Int> = []
        
        for (i, line) in lines.enumerated() {
            if skipNextLine.contains(i) { continue }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            
            let linePairs = splitMultiLabelLine(trimmed)
            
            if !linePairs.isEmpty {
                for (label, value) in linePairs {
                    if value.isEmpty && i + 1 < lines.count && !skipNextLine.contains(i + 1) {
                        // Value on next line — but only if next line isn't itself a label line
                        let nextLine = lines[i + 1].trimmingCharacters(in: .whitespaces)
                        let nextPairs = splitMultiLabelLine(nextLine)
                        if nextPairs.isEmpty && !nextLine.isEmpty {
                            // Next line is plain text, grab it
                            pairs.append((label, nextLine))
                            skipNextLine.insert(i + 1)
                        } else {
                            pairs.append((label, ""))
                        }
                    } else {
                        pairs.append((label, value))
                    }
                }
            }
            
            // Also check "LABEL value" patterns (no colon) for financial fields
            let upper = trimmed.uppercased()
            if upper.hasPrefix("AMOUNT DUE") {
                let val = extractAmount(from: trimmed)
                if !val.isEmpty { info.amountDue = val }
            } else if upper.hasPrefix("TOTAL CHARGES") {
                let val = extractAmount(from: trimmed)
                if !val.isEmpty { info.totalCharges = val }
            } else if upper.hasPrefix("INSURANCE ADJUSTMENT") || upper.hasPrefix("INS. ADJUSTMENT") || upper.hasPrefix("INS ADJ") {
                let val = extractAmount(from: trimmed)
                if !val.isEmpty { info.insuranceAdjustment = val }
            } else if upper.hasPrefix("INSURANCE PAID") || upper.hasPrefix("INS. PAID") || upper.hasPrefix("INS PAID") {
                let val = extractAmount(from: trimmed)
                if !val.isEmpty { info.insurancePaid = val }
            }
        }
        
        #if DEBUG
        print("── extractBillInfo: \(pairs.count) label-value pairs ──")
        for (label, value) in pairs {
            print("  PAIR: \"\(label)\" → \"\(value)\"")
        }
        #endif
        
        // Process label-value pairs
        // Known label prefixes — if a value starts with one of these, it's a misparsed label, not a value
        let knownLabels = ["patient", "account", "date of service", "service date", "dos",
                           "date of birth", "dob", "mrn", "medical record", "insurance",
                           "policy", "member", "group", "provider", "phone", "fax",
                           "total charges", "amount due", "balance due"]
        
        func looksLikeLabel(_ text: String) -> Bool {
            let lower = text.lowercased()
            // Reject if it starts with a known field label followed by ":"
            for lbl in knownLabels {
                if lower.hasPrefix(lbl) && lower.dropFirst(lbl.count).trimmingCharacters(in: .whitespaces).hasPrefix(":") {
                    return true
                }
            }
            return false
        }
        
        for (label, value) in pairs {
            let key = label.lowercased()
                .replacingOccurrences(of: "#", with: "")
                .replacingOccurrences(of: ".", with: "")
                .trimmingCharacters(in: .whitespaces)
            let val = value.trimmingCharacters(in: .whitespaces)
            guard !val.isEmpty else { continue }
            // Skip if value looks like another label:value pair (safety net)
            guard !looksLikeLabel(val) else { continue }
            
            switch key {
            // Patient fields
            case "patient", "patient name", "name", "insured", "insured name", "subscriber", "subscriber name":
                if info.patientName.isEmpty && looksLikeName(val) { info.patientName = val }
            case "account", "account #", "account no", "acct", "acct #", "acct no", "account number":
                if info.accountNumber.isEmpty { info.accountNumber = val }
            case "date of service", "service date", "dos", "date(s) of service":
                // Value must look like a date (contains digits and / or -)
                if info.dateOfService.isEmpty && looksLikeDate(val) { info.dateOfService = val }
            case "date of birth", "dob", "birth date":
                if info.dateOfBirth.isEmpty && looksLikeDate(val) { info.dateOfBirth = val }
            case "address", "patient address":
                if info.patientAddress.isEmpty { info.patientAddress = val }
            case "mrn", "medical record", "medical record number", "med rec":
                // MRN should be an ID, not a section header (all caps multi-word)
                if info.mrn.isEmpty && !looksLikeSectionHeader(val) { info.mrn = val }
                
            // Insurance fields
            case "insurance", "insurance company", "carrier", "payer", "ins":
                // Insurance companies don't typically look like person names (2-3 words, no company indicators)
                // Common insurance indicators
                let insuranceIndicators = ["insurance", "health", "blue", "cross", "shield", "aetna",
                    "cigna", "united", "humana", "kaiser", "medicare", "medicaid", "tricare",
                    "anthem", "wellpoint", "molina", "centene", "group", "plan", "network",
                    "mutual", "benefit", "care", "medical", "hmo", "ppo", "inc", "corp", "llc"]
                let lowerVal = val.lowercased()
                let hasInsuranceIndicator = insuranceIndicators.contains(where: { lowerVal.contains($0) })
                
                if info.insuranceName.isEmpty {
                    if hasInsuranceIndicator || !looksLikeName(val) {
                        // Looks like a company name
                        info.insuranceName = val
                    } else if info.patientName.isEmpty {
                        // Looks like a person name — probably the patient, not the insurer
                        info.patientName = val
                    } else {
                        // Both filled or doesn't fit — store as insurance anyway
                        info.insuranceName = val
                    }
                }
            case "policy", "policy #", "policy no", "policy number":
                if info.policyNumber.isEmpty { info.policyNumber = val }
            case "member id", "member", "member #", "subscriber id", "id":
                if info.memberId.isEmpty && val.count >= 4 { info.memberId = val }
            case "group", "group #", "group no", "group number", "grp":
                if info.groupNumber.isEmpty { info.groupNumber = val }
                
            // Provider fields
            case "provider", "provider name", "facility", "hospital", "clinic":
                if info.providerName.isEmpty { info.providerName = val }
            case "phone", "tel", "telephone":
                if info.providerPhone.isEmpty && looksLikePhone(val) { info.providerPhone = val }
            case "fax":
                if info.providerFax.isEmpty && looksLikePhone(val) { info.providerFax = val }
                
            // Financial
            case "total charges", "total", "charges":
                if info.totalCharges.isEmpty { info.totalCharges = extractAmount(from: val).isEmpty ? val : extractAmount(from: val) }
            case "amount due", "balance due", "patient balance", "you owe", "total due":
                if info.amountDue.isEmpty { info.amountDue = extractAmount(from: val).isEmpty ? val : extractAmount(from: val) }
            case "insurance paid", "ins paid", "insurance payment":
                if info.insurancePaid.isEmpty { info.insurancePaid = extractAmount(from: val).isEmpty ? val : extractAmount(from: val) }
            case "insurance adjustment", "adjustment", "ins adjustment":
                if info.insuranceAdjustment.isEmpty { info.insuranceAdjustment = extractAmount(from: val).isEmpty ? val : extractAmount(from: val) }
                
            default:
                break
            }
        }
        
        // ── Post-processing: fix common mis-assignments ──
        
        // If MRN contains a known label prefix, it was wrongly grabbed — clear it
        if looksLikeLabel(info.mrn) { info.mrn = "" }
        if looksLikeLabel(info.policyNumber) { info.policyNumber = "" }
        
        // If insurance name looks like a person name and patient name is empty, swap
        if !info.insuranceName.isEmpty && info.patientName.isEmpty && looksLikeName(info.insuranceName) {
            info.patientName = info.insuranceName
            info.insuranceName = ""
        }
        
        // If patient name is still empty, check if any extracted value resembles a name
        // that got placed in the wrong field
        if info.patientName.isEmpty {
            // Check MRN, policyNumber, groupNumber — they shouldn't contain names
            for field in [info.mrn, info.memberId, info.groupNumber] {
                if looksLikeName(field) {
                    info.patientName = field
                    break
                }
            }
        }
        
        // Try to extract provider name from header (usually first bold/large text)
        if info.providerName.isEmpty {
            // First few lines often contain the provider/facility name
            for line in lines.prefix(5) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                // Skip lines that look like labels, addresses, or phone numbers
                if trimmed.contains(":") || looksLikePhone(trimmed) || trimmed.count < 5 { continue }
                // Provider names are typically ALL CAPS or Title Case, longer than a few words
                let words = trimmed.split(separator: " ")
                if words.count >= 2 && (trimmed == trimmed.uppercased() || words.allSatisfy({ $0.first?.isUppercase == true })) {
                    // Skip if it looks like an address
                    if !looksLikeAddress(trimmed) {
                        info.providerName = trimmed
                        break
                    }
                }
            }
        }
        
        // Extract provider address from lines near provider name
        if info.providerAddress.isEmpty, !info.providerName.isEmpty,
           let provIdx = lines.firstIndex(where: { $0.localizedCaseInsensitiveContains(info.providerName.prefix(20)) }) {
            // Check next few lines for address
            var addrParts: [String] = []
            for offset in 1...3 where provIdx + offset < lines.count {
                let line = lines[provIdx + offset].trimmingCharacters(in: .whitespaces)
                if line.contains(":") { break } // Hit a label, stop
                if looksLikeAddress(line) || looksLikePhone(line) {
                    if looksLikePhone(line) {
                        if info.providerPhone.isEmpty { info.providerPhone = line }
                    } else {
                        addrParts.append(line)
                    }
                } else if line.count > 10 && (line.contains(",") || matchesZip(line)) {
                    addrParts.append(line)
                } else {
                    break
                }
            }
            if !addrParts.isEmpty { info.providerAddress = addrParts.joined(separator: ", ") }
        }
        
        #if DEBUG
        print("── extractBillInfo RESULTS ──")
        print("  Patient: \(info.patientName)")
        print("  Account#: \(info.accountNumber)")
        print("  DOS: \(info.dateOfService)")
        print("  DOB: \(info.dateOfBirth)")
        print("  MRN: \(info.mrn)")
        print("  Insurance: \(info.insuranceName)")
        print("  Policy#: \(info.policyNumber)")
        print("  MemberID: \(info.memberId)")
        print("  Group#: \(info.groupNumber)")
        print("  Provider: \(info.providerName)")
        print("  Total: \(info.totalCharges) Due: \(info.amountDue)")
        #endif
        
        return info
    }
    
    // MARK: - Bill Info Parsing Helpers
    
    private func extractAmount(from text: String) -> String {
        // Match $X,XXX.XX or -$X,XXX.XX patterns
        let pattern = #"-?\$[\d,]+\.?\d{0,2}"#
        if let range = text.range(of: pattern, options: .regularExpression) {
            return String(text[range])
        }
        return ""
    }
    
    private func looksLikeName(_ text: String) -> Bool {
        let words = text.split(separator: " ")
        if words.count < 2 || words.count > 5 { return false }
        // Names typically have capitalized words, no digits
        let hasDigits = text.rangeOfCharacter(from: .decimalDigits) != nil
        return !hasDigits && words.allSatisfy { $0.first?.isLetter == true }
    }
    
    private func looksLikePhone(_ text: String) -> Bool {
        let digits = text.filter { $0.isNumber }
        return digits.count >= 10 && digits.count <= 11
    }
    
    private func looksLikeAddress(_ text: String) -> Bool {
        let upper = text.uppercased()
        // Common address indicators
        let indicators = ["STREET", "ST.", "AVE", "AVENUE", "BLVD", "DRIVE", "DR.", "ROAD", "RD.",
                          "LANE", "LN.", "WAY", "SUITE", "STE", "FLOOR", "FL ", "P.O. BOX", "PO BOX"]
        if indicators.contains(where: { upper.contains($0) }) { return true }
        // Address typically starts with a number
        if text.first?.isNumber == true && text.count > 10 { return true }
        // City, State ZIP pattern
        if matchesZip(text) { return true }
        return false
    }
    
    private func matchesZip(_ text: String) -> Bool {
        text.range(of: #"\b\d{5}(-\d{4})?\b"#, options: .regularExpression) != nil
    }
    
    /// Check if text looks like a date (e.g. 11/15/2024, 2024-11-15, 01-15-24)
    private func looksLikeDate(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        // Must contain at least one separator (/ or -)
        guard trimmed.contains("/") || trimmed.contains("-") else { return false }
        // Must have digits
        let digits = trimmed.filter { $0.isNumber }
        guard digits.count >= 4 && digits.count <= 8 else { return false }
        // Common date patterns: MM/DD/YYYY, MM-DD-YYYY, YYYY-MM-DD, M/D/YY
        let datePatterns = [
            #"\d{1,2}/\d{1,2}/\d{2,4}"#,   // M/D/YY or MM/DD/YYYY
            #"\d{4}-\d{1,2}-\d{1,2}"#,       // YYYY-MM-DD
            #"\d{1,2}-\d{1,2}-\d{2,4}"#,     // MM-DD-YYYY or M-D-YY
        ]
        return datePatterns.contains(where: { trimmed.range(of: $0, options: .regularExpression) != nil })
    }
    
    /// Check if text looks like a section header (all caps, multiple words, no punctuation values)
    private func looksLikeSectionHeader(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let words = trimmed.split(separator: " ")
        // Section headers: 2+ words, all uppercase, no digits/special chars typical of IDs
        guard words.count >= 2 else { return false }
        // If it has digits, it's likely an ID not a header
        if trimmed.rangeOfCharacter(from: .decimalDigits) != nil { return false }
        // Check if all letters are uppercase
        let letters = trimmed.filter { $0.isLetter }
        guard !letters.isEmpty else { return false }
        return letters == letters.uppercased()
    }

    
    // ─────────────────────────────────────────────
    // MARK: - Column-Aware Table Parser
    // ─────────────────────────────────────────────
    
    private enum CellKind { case code, amount, text }
    
    private func isIsolatedCode(_ text: String, matchRange: Range<String.Index>) -> Bool {
        let full = text
        if matchRange.lowerBound > full.startIndex {
            let prevIdx = full.index(before: matchRange.lowerBound)
            let prev = full[prevIdx]
            if prev.isNumber { return false }
            if prev == "-" && prevIdx > full.startIndex {
                let bh = full.index(before: prevIdx)
                if full[bh].isNumber { return false }
            }
        }
        if matchRange.upperBound < full.endIndex {
            let next = full[matchRange.upperBound]
            if next.isNumber { return false }
            if next == "-" {
                let ah = full.index(after: matchRange.upperBound)
                if ah < full.endIndex && full[ah].isNumber { return false }
            }
        }
        let codeStr = String(full[matchRange])
        if codeStr.range(of: #"^\d{5}$"#, options: .regularExpression) != nil {
            let before = String(full[full.startIndex..<matchRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            if before.count >= 2 {
                let lastTwo = String(before.suffix(2)).uppercased()
                let states: Set<String> = ["AL","AK","AZ","AR","CA","CO","CT","DE","FL","GA","HI",
                    "IL","IN","IA","KS","KY","LA","ME","MD","MA","MI","MN","MS","MO","MT","NE","NV",
                    "NH","NJ","NM","NY","NC","ND","OH","OK","OR","PA","RI","SC","SD","TN","TX","UT",
                    "VT","VA","WA","WV","WI","WY","DC"]
                if states.contains(lastTwo) {
                    let bs = before.dropLast(2).trimmingCharacters(in: .whitespaces)
                    if bs.isEmpty || !bs.last!.isLetter { return false }
                }
            }
        }
        return true
    }
    
    private func looksLikeIdentifierCell(_ text: String) -> Bool {
        let u = text.uppercased()
        let patterns = [
            #"(?:ACCT|ACCOUNT|POLICY|MRN|AET|ID\s*#?)[\s#:.\-]*\d"#,
            #"\(\d{3}\)\s*\d{3}"#,
            #"\d{3}[\-\.]\d{3}[\-\.]\d{4}"#,
            #"(?:FAX|PHONE|TEL|PH)[\s:]*"#,
            #"PO\s+BOX"#,
            #"\d+\s+\w+\s+(?:DRIVE|DR|STREET|ST|AVE|AVENUE|BLVD|ROAD|RD|WAY|LN|LANE|CT|COURT)"#,
            #"WWW\.\w+|HTTP"#,
        ]
        for pat in patterns {
            if u.range(of: pat, options: .regularExpression) != nil { return true }
        }
        return false
    }
    
    /// Returns (kind, extractedCode). extractedCode is non-empty only for .code cells.
    private func classifyCell(_ text: String) -> (CellKind, String) {
        let t = text.trimmingCharacters(in: .whitespaces)
        let u = t.uppercased()
        
        // Dollar amount
        if t.range(of: #"^\$?\s*-?\d{1,3}(?:,\d{3})*\.\d{2}\s*$"#, options: .regularExpression) != nil {
            return (.amount, "")
        }
        
        // Date-only cells: "11/15/24", "11-15-2024", "2024-11-15", etc.
        if t.range(of: #"^\d{1,2}[/\-]\d{1,2}[/\-]\d{2,4}$"#, options: .regularExpression) != nil { return (.text, "") }
        if t.range(of: #"^\d{4}[/\-]\d{1,2}[/\-]\d{1,2}$"#, options: .regularExpression) != nil { return (.text, "") }
        
        // Quantity cells: plain "1", "2", etc.
        if t.range(of: #"^\d{1,2}$"#, options: .regularExpression) != nil && Int(t) ?? 0 < 100 { return (.text, "") }
        
        // Skip identifier cells (addresses, phone numbers, account numbers)
        if looksLikeIdentifierCell(u) { return (.text, "") }
        
        // CPT
        if let r = u.range(of: #"\b\d{5}\b"#, options: .regularExpression) {
            let code = String(u[r])
            if isValidCPT(code) && isIsolatedCode(u, matchRange: r) { return (.code, code) }
        }
        // HCPCS
        if let r = u.range(of: #"\b[A-V]\d{4}\b"#, options: .regularExpression) {
            if isIsolatedCode(u, matchRange: r) { return (.code, String(u[r])) }
        }
        // ICD-10
        if let r = u.range(of: #"\b[A-TV-Z]\d{2}\.?\d{0,4}\b"#, options: .regularExpression) {
            let code = String(u[r])
            if code.count >= 3 && isIsolatedCode(u, matchRange: r) { return (.code, code) }
        }
        // UB-04 Revenue codes: 4-digit numeric (0001-9999), common on hospital bills
        // e.g. 0120 = Room & Board Semi-Private
        if let r = u.range(of: #"\b0[0-9]{3}\b"#, options: .regularExpression) {
            let code = String(u[r])
            if isIsolatedCode(u, matchRange: r) { return (.code, code) }
        }
        // Alpha-only billing codes: 2-6 uppercase letters used by some facilities
        // e.g. PHARM, NURS, ROOM — must be short and not a common English/bill word.
        // Require the cell to be ≤6 chars to exclude full words like CHARGES, AMOUNT.
        let alphaExclude: Set<String> = [
            "DATE", "CODE", "DESC", "QTY", "AMT", "AND", "FOR", "THE", "WITH",
            "CHARGES", "AMOUNT", "TOTAL", "PAID", "PALD", "INSURANCE", "PATIENT",
            "PROVIDER", "BALANCE", "STATEMENT", "SERVICES", "INPATIENT", "OUTPATIENT",
            "PROCEDURE", "DESCRIPTION", "QUANTITY", "SUBTOTAL", "DUE", "ACCOUNT",
            "ADMISSION", "DISCHARGE", "DIAGNOSIS", "FACILITY", "HOSPITAL", "MEDICAL",
            "OFFICE", "VISIT", "CARE", "HIGH", "DAILY", "SEMI", "PRIVATE", "BOARD",
            "ROOM", "KNEE", "THERAPY", "PHYSICAL", "LABORATORY", "RADIOLOGY",
            "INITIAL", "SUBSEQUENT", "COMPREHENSIVE", "COMPLETE", "BLOOD", "COUNT",
            "ANESTHESIA", "ARTHROPLASTY", "REPLACEMENT", "ULTRASOUND", "ABDOMEN"
        ]
        if u.range(of: #"^[A-Z]{2,6}$"#, options: .regularExpression) != nil,
           !alphaExclude.contains(u),
           !u.hasPrefix("WITH"), !u.hasPrefix("INPAT"), !u.hasPrefix("OUTPAT") {
            return (.code, u)
        }
        return (.text, "")
    }
    
    private func buildCodesFromColumns(cells: [OCRTextCell]) -> ([ScannedCode], String) {
        guard !cells.isEmpty else { return ([], "No text detected") }
        
        struct Tagged {
            let cell: OCRTextCell
            let kind: CellKind
            let extractedCode: String
        }
        let tagged: [Tagged] = cells.map {
            let (k, c) = classifyCell($0.text)
            return Tagged(cell: $0, kind: k, extractedCode: c)
        }
        
        let codeTagged   = tagged.filter { $0.kind == .code }
        let amountTagged = tagged.filter { $0.kind == .amount }
        let textTagged   = tagged.filter { $0.kind == .text }
        var debug = "OCR: \(cells.count) cells (\(codeTagged.count)c/\(amountTagged.count)a/\(textTagged.count)t)"
        
        let detectedCodes = codeTagged.map { $0.extractedCode }
        if !detectedCodes.isEmpty { debug += "\nDetected: \(detectedCodes.joined(separator: ", "))" }
        
        // Group into rows by Y — use first cell as anchor (no drifting average)
        let sorted = tagged.sorted { $0.cell.midY > $1.cell.midY }
        var rows: [[Tagged]] = []
        var curRow: [Tagged] = []
        var anchorY: CGFloat = -1
        let yTol: CGFloat = 0.010  // tighter: ~1% of image height
        
        for item in sorted {
            if anchorY < 0 || abs(item.cell.midY - anchorY) <= yTol {
                curRow.append(item)
                if anchorY < 0 { anchorY = item.cell.midY }
            } else {
                if !curRow.isEmpty { rows.append(curRow.sorted { $0.cell.midX < $1.cell.midX }) }
                curRow = [item]; anchorY = item.cell.midY
            }
        }
        if !curRow.isEmpty { rows.append(curRow.sorted { $0.cell.midX < $1.cell.midX }) }
        
        let rowsWithCodes = rows.filter { row in row.contains { $0.kind == .code } }.count
        debug += "\nRows: \(rows.count) total, \(rowsWithCodes) with codes"
        
        for (i, row) in rows.enumerated() {
            let parts = row.map { item -> String in
                switch item.kind {
                case .code: return "C(\(item.extractedCode))"
                case .amount: return "A(\(item.cell.text.prefix(8)))"
                case .text: return "T(\(item.cell.text.prefix(12)))"
                }
            }
            let y = row.first.map { String(format: "%.3f", $0.cell.midY) } ?? "?"
            debug += "\n R\(i) y\(y): \(parts.joined(separator: "|"))"
        }
        
        let codeColX:   CGFloat? = codeTagged.isEmpty   ? nil : codeTagged.map(\.cell.midX).reduce(0, +) / CGFloat(codeTagged.count)
        let amountColX: CGFloat? = amountTagged.isEmpty ? nil : amountTagged.map(\.cell.midX).reduce(0, +) / CGFloat(amountTagged.count)
        
        var parsed: [ParsedBillRow] = []
        
        // Words that appear as column headers or financial summary labels — never valid billing codes
        let billHeaderWords: Set<String> = [
            "CHARGES", "AMOUNT", "TOTAL", "PAID", "PALD", "INSURANCE", "PATIENT",
            "PROVIDER", "BALANCE", "STATEMENT", "SERVICES", "INPATIENT", "OUTPATIENT",
            "PROCEDURE", "DESCRIPTION", "QUANTITY", "SUBTOTAL", "DUE", "ACCOUNT",
            "DATE", "CODE", "DESC", "QTY", "AMT", "WITH", "CARE", "HIGH", "DAILY",
            "INITIAL", "SUBSEQUENT", "COMPREHENSIVE", "COMPLETE"
        ]

        for row in rows {
            // Count code cells in this row
            let codeCells = row.filter { $0.kind == .code }
            let amountCells = row.filter { $0.kind == .amount }
            let textCells = row.filter { $0.kind == .text }

            // Skip table-header rows: no amounts AND all "codes" are header words
            // (e.g. "Date | Code | Description | Qty | Amount | Amount")
            if amountCells.isEmpty && codeCells.allSatisfy({ billHeaderWords.contains($0.extractedCode.uppercased()) }) {
                continue
            }

            // Skip financial-summary rows where the "code" is a summary label
            // (e.g. TOTAL, CHARGES, PALD/PAID)
            if codeCells.count == 1 && billHeaderWords.contains(codeCells[0].extractedCode.uppercased()) {
                continue
            }
            
            if codeCells.count > 1 {
                // Multiple codes merged into one row — split each into its own result
                for codeItem in codeCells {
                    var pr = ParsedBillRow()
                    pr.code = codeItem.extractedCode
                    pr.codeType = detectType(codeItem.extractedCode)
                    pr.rawTexts = row.map(\.cell.text)
                    // Nearest amount by X
                    if let nearest = amountCells.min(by: { abs($0.cell.midX - codeItem.cell.midX) < abs($1.cell.midX - codeItem.cell.midX) }) {
                        pr.amount = parseAmount(nearest.cell.text)
                    }
                    // Nearest text cells as description
                    pr.description = textCells
                        .filter { abs($0.cell.midY - codeItem.cell.midY) < 0.008 }
                        .sorted { $0.cell.midX < $1.cell.midX }
                        .map(\.cell.text).joined(separator: " ")
                    parsed.append(pr)
                }
            } else {
                // Single or no code — standard logic
                var pr = ParsedBillRow()
                var descParts: [String] = []
                
                for item in row {
                    pr.rawTexts.append(item.cell.text)
                    switch item.kind {
                    case .code:
                        if pr.code.isEmpty {
                            pr.code = item.extractedCode
                            pr.codeType = detectType(item.extractedCode)
                        } else {
                            descParts.append(item.cell.text)
                        }
                    case .amount:
                        if pr.amount == nil || (amountColX != nil && abs(item.cell.midX - amountColX!) < 0.15) {
                            pr.amount = parseAmount(item.cell.text)
                        }
                    case .text:
                        if let cx = codeColX, abs(item.cell.midX - cx) < 0.08 { continue }
                        if let ax = amountColX, abs(item.cell.midX - ax) < 0.08 { continue }
                        descParts.append(item.cell.text)
                    }
                }
                
                if pr.code.isEmpty {
                    let combined = row.map(\.cell.text).joined(separator: " ")
                    if let found = findInlineCode(combined) {
                        pr.code = found.code; pr.codeType = found.type
                        descParts = [combined.replacingOccurrences(of: found.code, with: "", options: .caseInsensitive)]
                        if pr.amount == nil { pr.amount = lastAmount(in: combined) }
                    }
                }
                
                if pr.code.isEmpty {
                    for item in row where item.kind == .text {
                        if let found = findInlineCode(item.cell.text) {
                            pr.code = found.code; pr.codeType = found.type
                            break
                        }
                    }
                }
                
                var rawDesc = descParts.joined(separator: " ")
                    .trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "|-:·,"))
                    .trimmingCharacters(in: .whitespaces)

                // Strip dollar amounts from description
                if let rx = try? NSRegularExpression(pattern: #"\$?\s*-?\d{1,3}(?:,\d{3})*\.\d{2}"#) {
                    let r = NSRange(rawDesc.startIndex..., in: rawDesc)
                    rawDesc = rx.stringByReplacingMatches(in: rawDesc, range: r, withTemplate: "")
                        .trimmingCharacters(in: .whitespaces)
                }
                // Strip standard date formats (11/15/24)
                if let rx = try? NSRegularExpression(pattern: #"\d{1,2}/\d{1,2}/\d{2,4}"#) {
                    let r = NSRange(rawDesc.startIndex..., in: rawDesc)
                    rawDesc = rx.stringByReplacingMatches(in: rawDesc, range: r, withTemplate: "")
                        .trimmingCharacters(in: .whitespaces)
                }
                // Strip leading date-range prefixes e.g. "10/11-16 " or "10/13-18 "
                if let rx = try? NSRegularExpression(pattern: #"^\d{1,2}/\d{1,2}[-–]\d{1,4}\s+"#) {
                    let r = NSRange(rawDesc.startIndex..., in: rawDesc)
                    rawDesc = rx.stringByReplacingMatches(in: rawDesc, range: r, withTemplate: "")
                        .trimmingCharacters(in: .whitespaces)
                }
                // Strip trailing lone quantity digits (e.g. "Anesthesia - knee replacement 1")
                if let rx = try? NSRegularExpression(pattern: #"\s+\d{1,2}$"#) {
                    let r = NSRange(rawDesc.startIndex..., in: rawDesc)
                    rawDesc = rx.stringByReplacingMatches(in: rawDesc, range: r, withTemplate: "")
                        .trimmingCharacters(in: .whitespaces)
                }
                pr.description = rawDesc
                
                if !pr.code.isEmpty { parsed.append(pr) }
            }
        }
        
        let parsedCodes = parsed.map(\.code)
        debug += "\nParsed: \(parsed.count) rows with codes: \(parsedCodes.joined(separator: ", "))"
        
        var results: [ScannedCode] = []
        var seen = Set<String>()
        
        for row in parsed {
            guard !seen.contains(row.code) else { continue }
            seen.insert(row.code)
            
            var desc = row.description
            var matched: MedicalCode?
            if let m = appState.cloudKitService.lookupCode(row.code) {
                matched = m
                if desc.count < 5 { desc = m.shortDescription }
            }
            
            var sc = ScannedCode(
                rawText: row.rawTexts.joined(separator: " | "),
                detectedCode: row.code,
                scannedDescription: desc,
                possibleType: row.codeType,
                timestamp: Date()
            )
            sc.matchedMedicalCode = matched
            sc.lookupFailed = matched == nil
            sc.scannedPrice = row.amount
            results.append(sc)
            
            if matched == nil {
                var c = row.code
                // OCR commonly misreads "9" as "8" at the start of 5-digit CPT codes.
                // If lookup failed and code starts with 8, try the 9-variant.
                if c.count == 5 && c.hasPrefix("8"),
                   let corrected = appState.cloudKitService.lookupCode("9" + c.dropFirst()) {
                    sc.detectedCode = "9" + c.dropFirst()
                    sc.matchedMedicalCode = corrected
                    sc.lookupFailed = false
                    if var last = results.last {
                        last = sc
                        results[results.count - 1] = last
                    }
                    c = sc.detectedCode
                } else {
                    Task { await lookupAsync(c) }
                }
            }
        }
        
        debug += "\nResults: \(results.count) unique codes"
        
        return (results, debug)
    }

    
    // ─────────────────────────────────────────────
    // MARK: - Parsing Helpers
    // ─────────────────────────────────────────────
    
    private func detectType(_ code: String) -> MedicalCodeType? {
        let u = code.uppercased()
        if u.range(of: #"^\d{5}$"#, options: .regularExpression) != nil && isValidCPT(u) { return .cpt }
        if u.range(of: #"^[A-V]\d{4}$"#, options: .regularExpression) != nil { return .hcpcs }
        if u.range(of: #"^[A-TV-Z]\d{2}\.?\d{0,4}$"#, options: .regularExpression) != nil { return .icd10 }
        return nil
    }
    
    private struct InlineMatch { let code: String; let type: MedicalCodeType }
    
    private func findInlineCode(_ text: String) -> InlineMatch? {
        let u = text.uppercased()
        // Don't filter by context here — inline extraction handles combined row text
        // where dates, descriptions etc. naturally appear alongside codes.
        // Isolation check handles the digit-adjacency cases.
        if let r = u.range(of: #"\b\d{5}\b"#, options: .regularExpression), isValidCPT(String(u[r])), isIsolatedCode(u, matchRange: r) {
            return InlineMatch(code: String(u[r]), type: .cpt)
        }
        if let r = u.range(of: #"\b[A-V]\d{4}\b"#, options: .regularExpression), isIsolatedCode(u, matchRange: r) {
            return InlineMatch(code: String(u[r]), type: .hcpcs)
        }
        if let r = u.range(of: #"\b[A-TV-Z]\d{2}\.?\d{0,4}\b"#, options: .regularExpression), String(u[r]).count >= 3, isIsolatedCode(u, matchRange: r) {
            return InlineMatch(code: String(u[r]), type: .icd10)
        }
        // UB-04 revenue codes (0001-0999)
        if let r = u.range(of: #"\b0[0-9]{3}\b"#, options: .regularExpression), isIsolatedCode(u, matchRange: r) {
            return InlineMatch(code: String(u[r]), type: .hcpcs)
        }
        // Alpha-only billing codes (PHARM, NURS, etc.) — same exclusion as classifyCell
        let alphaSkip: Set<String> = [
            "DATE", "CODE", "DESC", "QTY", "AMT", "AND", "FOR", "THE", "WITH",
            "CHARGES", "AMOUNT", "TOTAL", "PAID", "PALD", "INSURANCE", "PATIENT",
            "PROVIDER", "BALANCE", "STATEMENT", "SERVICES", "INPATIENT", "OUTPATIENT",
            "PROCEDURE", "DESCRIPTION", "QUANTITY", "SUBTOTAL", "DUE", "ACCOUNT",
            "CARE", "HIGH", "DAILY", "SEMI", "ROOM", "KNEE", "INITIAL", "SUBSEQUENT"
        ]
        if let r = u.range(of: #"\b[A-Z]{2,6}\b"#, options: .regularExpression) {
            let word = String(u[r])
            if !alphaSkip.contains(word), isIsolatedCode(u, matchRange: r) {
                return InlineMatch(code: word, type: .hcpcs)
            }
        }
        return nil
    }
    
    private func parseAmount(_ text: String) -> Double? {
        Double(text.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces))
    }
    
    private func lastAmount(in text: String) -> Double? {
        guard let rx = try? NSRegularExpression(pattern: #"\$?\s*(\d{1,3}(?:,\d{3})*\.\d{2})"#) else { return nil }
        let r = NSRange(text.startIndex..., in: text)
        guard let last = rx.matches(in: text, range: r).last, let vr = Range(last.range(at: 1), in: text) else { return nil }
        return Double(String(text[vr]).replacingOccurrences(of: ",", with: ""))
    }
    
    private func isValidCPT(_ code: String) -> Bool {
        guard code.count == 5, let n = Int(code) else { return false }
        return (n >= 100 && n <= 1999) || (n >= 10004 && n <= 69990) ||
               (n >= 70010 && n <= 79999) || (n >= 80047 && n <= 89398) ||
               (n >= 90281 && n <= 99607)
    }
    
    private func lookupAsync(_ code: String) async {
        if let mc = try? await appState.cloudKitService.fetchCode(byCode: code) {
            await MainActor.run {
                if let i = extractedCodes.firstIndex(where: { $0.detectedCode == code }) {
                    extractedCodes[i].matchedMedicalCode = mc
                    extractedCodes[i].isLookingUp = false
                    extractedCodes[i].lookupFailed = false
                }
            }
        }
    }
    
    // ─────────────────────────────────────────────
    // MARK: - Save Scan
    // ─────────────────────────────────────────────
    
    private func promptSaveScan() {
        // Pre-fill with facility/provider name if available
        let name = billInfo.providerName.trimmingCharacters(in: .whitespaces)
        if !name.isEmpty {
            saveScanName = name
        } else if !billInfo.patientName.isEmpty {
            saveScanName = "\(billInfo.patientName) Scan"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d, yyyy"
            saveScanName = "Scan \(formatter.string(from: Date()))"
        }
        showingSaveAlert = true
    }
    
    private func saveScan() {
        let name = saveScanName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        
        let scanId = UUID().uuidString
        
        // Build saved codes from extracted codes
        let savedCodes: [SavedScanCode] = extractedCodes.map { code in
            SavedScanCode(
                code: code.detectedCode,
                codeType: code.possibleType?.rawValue ?? "Unknown",
                description: code.bestDescription,
                scannedPrice: code.scannedPrice,
                databaseDescription: code.matchedMedicalCode?.shortDescription,
                databasePriceRange: code.matchedMedicalCode?.formattedPriceRange
            )
        }
        
        // Save the image as JPEG
        var imageFileName: String? = nil
        if let image = selectedImage, let jpegData = image.jpegData(compressionQuality: 0.8) {
            let imgName = "scan_\(scanId).jpg"
            if let url = scansDirectory()?.appendingPathComponent(imgName) {
                try? jpegData.write(to: url)
                imageFileName = imgName
            }
        }
        
        let savedScan = SavedScan(
            id: scanId,
            name: name,
            billInfo: billInfo,
            codes: savedCodes,
            scanDate: Date(),
            imageFileName: imageFileName
        )
        
        // Write JSON
        let fileName = savedScan.safeFileName + ".json"
        if let dir = scansDirectory() {
            let fileURL = dir.appendingPathComponent(fileName)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? encoder.encode(savedScan) {
                try? data.write(to: fileURL)
                savedFileName = fileName
                withAnimation { showingSavedConfirmation = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    withAnimation { showingSavedConfirmation = false }
                }
                #if DEBUG
                print("── Scan saved to: \(fileURL.path)")
                #endif
            }
        }
    }
    
    /// Returns (and creates if needed) the BillGuard/Scans directory in Documents
    private func scansDirectory() -> URL? {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        let scansDir = docs.appendingPathComponent("Scans")
        if !FileManager.default.fileExists(atPath: scansDir.path) {
            try? FileManager.default.createDirectory(at: scansDir, withIntermediateDirectories: true)
        }
        return scansDir
    }
    
    // ─────────────────────────────────────────────
    // MARK: - Navigation
    // ─────────────────────────────────────────────
    
    private func resetAll() {
        selectedImage = nil; showingResults = false; showingRegionSelector = false; isProcessing = false
        extractedText = ""; extractedCodes = []; selectedCodeIds = []; columnSummary = ""
        billInfo = ExtractedBillInfo()
        imageZoom = 1.0; imageOffset = .zero
        tableRegion = .init(center: .init(x: 0.5, y: 0.5), size: .init(width: 0.92, height: 0.55))
    }
    
    private func goBackToRegion() {
        showingResults = false; showingRegionSelector = true
        extractedText = ""; extractedCodes = []; selectedCodeIds = []; columnSummary = ""
        billInfo = ExtractedBillInfo()
    }
}

// ═══════════════════════════════════════════════════
// MARK: - Table Selection Region Model
// ═══════════════════════════════════════════════════

struct TableSelectionRegion {
    var center: CGPoint   // normalized 0–1
    var size: CGSize      // normalized 0–1
}

// ═══════════════════════════════════════════════════
// MARK: - Table Draggable Rectangle (unique to Scan Codes)
// ═══════════════════════════════════════════════════

/// A distinct table-style resizable rectangle with:
///  – dashed border, table icon label
///  – square corner handles (not circles like DraggableBox)
///  – midpoint edge handles (horizontal bars)
struct TableDraggableRect: View {
    @Binding var region: TableSelectionRegion
    let containerSize: CGSize
    let offset: CGPoint
    var zoomScale: CGFloat = 1.0
    
    private var boxFrame: CGRect {
        CGRect(
            x: offset.x + (region.center.x - region.size.width / 2) * containerSize.width,
            y: offset.y + (region.center.y - region.size.height / 2) * containerSize.height,
            width: region.size.width * containerSize.width,
            height: region.size.height * containerSize.height
        )
    }
    
    var body: some View {
        ZStack {
            // Dashed border + tinted fill
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.cyan.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(style: StrokeStyle(lineWidth: max(1, 2.5 / zoomScale), dash: [8, 4]))
                        .foregroundColor(.cyan)
                )
            
            // Label — keep readable size when zoomed
            if boxFrame.height > 36 {
                VStack {
                    HStack(spacing: 4) {
                        Image(systemName: "tablecells").font(.caption2)
                        Text("Table Area").font(.caption2).fontWeight(.bold)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.cyan.opacity(0.85))
                    .cornerRadius(4)
                    .scaleEffect(1.0 / max(1, zoomScale))
                    Spacer()
                }
                .padding(.top, 4)
            }
            
            // Column hint lines
            if boxFrame.width > 80 && boxFrame.height > 50 {
                GeometryReader { geo in
                    Path { path in
                        let x1 = geo.size.width * 0.30
                        let x2 = geo.size.width * 0.75
                        path.move(to: CGPoint(x: x1, y: 20))
                        path.addLine(to: CGPoint(x: x1, y: geo.size.height - 4))
                        path.move(to: CGPoint(x: x2, y: 20))
                        path.addLine(to: CGPoint(x: x2, y: geo.size.height - 4))
                    }
                    .stroke(Color.cyan.opacity(0.25), style: StrokeStyle(lineWidth: max(0.5, 1 / zoomScale), dash: [4, 4]))
                }
            }
            
            // Resize handles
            TableResizeHandles(region: $region, containerSize: containerSize, offset: offset, zoomScale: zoomScale)
        }
        .frame(width: max(30, boxFrame.width), height: max(20, boxFrame.height))
        .position(x: boxFrame.midX, y: boxFrame.midY)
        .gesture(
            DragGesture()
                .onChanged { val in
                    let nx = (val.location.x - offset.x) / containerSize.width
                    let ny = (val.location.y - offset.y) / containerSize.height
                    region.center.x = max(region.size.width / 2, min(1 - region.size.width / 2, nx))
                    region.center.y = max(region.size.height / 2, min(1 - region.size.height / 2, ny))
                }
        )
    }
}

// MARK: - Table Resize Handles

struct TableResizeHandles: View {
    @Binding var region: TableSelectionRegion
    let containerSize: CGSize
    let offset: CGPoint
    var zoomScale: CGFloat = 1.0
    
    private var handleSize: CGFloat { max(14, 20 / zoomScale) }
    private var edgeBarLength: CGFloat { max(20, 34 / zoomScale) }
    private var edgeBarThick: CGFloat { max(4, 7 / zoomScale) }
    
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            
            // ── Corner handles (squares) ──
            
            // Top-left
            cornerSquare
                .position(x: 0, y: 0)
                .gesture(DragGesture().onChanged { val in
                    resizeCorner(val.location, in: geo.size, corner: .topLeft)
                })
            
            // Top-right
            cornerSquare
                .position(x: w, y: 0)
                .gesture(DragGesture().onChanged { val in
                    resizeCorner(val.location, in: geo.size, corner: .topRight)
                })
            
            // Bottom-left
            cornerSquare
                .position(x: 0, y: h)
                .gesture(DragGesture().onChanged { val in
                    resizeCorner(val.location, in: geo.size, corner: .bottomLeft)
                })
            
            // Bottom-right
            cornerSquare
                .position(x: w, y: h)
                .gesture(DragGesture().onChanged { val in
                    resizeCorner(val.location, in: geo.size, corner: .bottomRight)
                })
            
            // ── Edge handles (capsules) ──
            
            // Top edge
            Capsule().fill(Color.cyan.opacity(0.85))
                .overlay(Capsule().stroke(Color.white, lineWidth: 1))
                .frame(width: min(edgeBarLength, w * 0.3), height: edgeBarThick)
                .position(x: w / 2, y: 0)
                .gesture(DragGesture().onChanged { val in
                    resizeEdge(val.location, in: geo.size, edge: .top)
                })
            
            // Bottom edge
            Capsule().fill(Color.cyan.opacity(0.85))
                .overlay(Capsule().stroke(Color.white, lineWidth: 1))
                .frame(width: min(edgeBarLength, w * 0.3), height: edgeBarThick)
                .position(x: w / 2, y: h)
                .gesture(DragGesture().onChanged { val in
                    resizeEdge(val.location, in: geo.size, edge: .bottom)
                })
            
            // Left edge
            Capsule().fill(Color.cyan.opacity(0.85))
                .overlay(Capsule().stroke(Color.white, lineWidth: 1))
                .frame(width: edgeBarThick, height: min(edgeBarLength, h * 0.3))
                .position(x: 0, y: h / 2)
                .gesture(DragGesture().onChanged { val in
                    resizeEdge(val.location, in: geo.size, edge: .leading)
                })
            
            // Right edge
            Capsule().fill(Color.cyan.opacity(0.85))
                .overlay(Capsule().stroke(Color.white, lineWidth: 1))
                .frame(width: edgeBarThick, height: min(edgeBarLength, h * 0.3))
                .position(x: w, y: h / 2)
                .gesture(DragGesture().onChanged { val in
                    resizeEdge(val.location, in: geo.size, edge: .trailing)
                })
        }
    }
    
    private var cornerSquare: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Color.cyan)
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.white, lineWidth: 1.5))
            .frame(width: handleSize, height: handleSize)
    }
    
    enum Corner { case topLeft, topRight, bottomLeft, bottomRight }
    enum Edge { case top, bottom, leading, trailing }
    
    /// Convert a drag point in handle-local space to normalized (0–1) image coordinates.
    private func localToNormalized(_ point: CGPoint, in size: CGSize) -> CGPoint {
        // The GeometryReader fills the box frame.
        // Box top-left in parent = offset + (region edge) * containerSize
        let boxOriginX = offset.x + (region.center.x - region.size.width / 2) * containerSize.width
        let boxOriginY = offset.y + (region.center.y - region.size.height / 2) * containerSize.height
        
        // Global position of the drag point
        let globalX = boxOriginX + point.x
        let globalY = boxOriginY + point.y
        
        // Normalized to image space
        let nx = (globalX - offset.x) / containerSize.width
        let ny = (globalY - offset.y) / containerSize.height
        return CGPoint(x: max(0, min(1, nx)), y: max(0, min(1, ny)))
    }
    
    private func resizeCorner(_ local: CGPoint, in size: CGSize, corner: Corner) {
        let norm = localToNormalized(local, in: size)
        let minS: CGFloat = 0.08
        
        var left   = region.center.x - region.size.width / 2
        var right  = region.center.x + region.size.width / 2
        var top    = region.center.y - region.size.height / 2
        var bottom = region.center.y + region.size.height / 2
        
        switch corner {
        case .topLeft:     left = min(norm.x, right - minS);  top = min(norm.y, bottom - minS)
        case .topRight:    right = max(norm.x, left + minS);  top = min(norm.y, bottom - minS)
        case .bottomLeft:  left = min(norm.x, right - minS);  bottom = max(norm.y, top + minS)
        case .bottomRight: right = max(norm.x, left + minS);  bottom = max(norm.y, top + minS)
        }
        
        region.center = CGPoint(x: (left + right) / 2, y: (top + bottom) / 2)
        region.size = CGSize(width: right - left, height: bottom - top)
    }
    
    private func resizeEdge(_ local: CGPoint, in size: CGSize, edge: Edge) {
        let norm = localToNormalized(local, in: size)
        let minS: CGFloat = 0.08
        
        var left   = region.center.x - region.size.width / 2
        var right  = region.center.x + region.size.width / 2
        var top    = region.center.y - region.size.height / 2
        var bottom = region.center.y + region.size.height / 2
        
        switch edge {
        case .top:      top    = min(norm.y, bottom - minS)
        case .bottom:   bottom = max(norm.y, top + minS)
        case .leading:  left   = min(norm.x, right - minS)
        case .trailing: right  = max(norm.x, left + minS)
        }
        
        region.center = CGPoint(x: (left + right) / 2, y: (top + bottom) / 2)
        region.size = CGSize(width: right - left, height: bottom - top)
    }
}

// ═══════════════════════════════════════════════════
// MARK: - Table Region Dim Overlay
// ═══════════════════════════════════════════════════

struct TableRegionDimOverlay: View {
    let region: TableSelectionRegion
    let containerSize: CGSize
    let offset: CGPoint
    
    var body: some View {
        Canvas { context, size in
            let fullRect = CGRect(origin: .zero, size: size)
            context.fill(Path(fullRect), with: .color(.black.opacity(0.4)))
            
            let bx = offset.x + (region.center.x - region.size.width / 2) * containerSize.width
            let by = offset.y + (region.center.y - region.size.height / 2) * containerSize.height
            let bw = region.size.width * containerSize.width
            let bh = region.size.height * containerSize.height
            let boxRect = CGRect(x: bx, y: by, width: bw, height: bh)
            
            context.blendMode = .destinationOut
            context.fill(Path(boxRect), with: .color(.white))
        }
        .allowsHitTesting(false)
    }
}

// ═══════════════════════════════════════════════════
// MARK: - Scan Code Result Row
// ═══════════════════════════════════════════════════

struct ScanCodeResultRow: View {
    let code: ScannedCode
    let isSelected: Bool
    let onToggle: () -> Void
    let onTap: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Button { onToggle() } label: {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundColor(isSelected ? .accentColor : .secondary)
            }
            .buttonStyle(.plain)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(code.detectedCode)
                        .font(.system(.headline, design: .monospaced))
                        .foregroundColor(.accentColor)
                    Text(code.displayType)
                        .font(.caption2).fontWeight(.medium)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(typeColor.opacity(0.15))
                        .foregroundColor(typeColor).cornerRadius(4)
                    if code.matchedMedicalCode != nil {
                        Image(systemName: "checkmark.seal.fill").font(.caption2).foregroundColor(.green)
                    }
                }
                if !code.bestDescription.isEmpty {
                    Text(code.bestDescription).font(.subheadline).foregroundColor(.secondary).lineLimit(2)
                }
                HStack(spacing: 12) {
                    if let p = code.scannedPrice, p > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "dollarsign.circle.fill").font(.caption2).foregroundColor(.orange)
                            Text(p, format: .currency(code: "USD")).font(.caption).fontWeight(.semibold)
                        }
                    }
                    if let m = code.matchedMedicalCode, m.hasValidPricing {
                        HStack(spacing: 4) {
                            Image(systemName: "chart.bar.fill").font(.caption2).foregroundColor(.green)
                            Text("Avg: \(m.formattedPriceRange)").font(.caption2).foregroundColor(.green)
                        }
                    }
                    if code.isLookingUp { ProgressView().scaleEffect(0.6) }
                }
            }
            
            Spacer()
            
            if code.matchedMedicalCode != nil {
                Button { onTap() } label: {
                    Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
                }.buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { onToggle() }
    }
    
    private var typeColor: Color {
        switch code.possibleType {
        case .cpt: return .blue; case .icd10: return .green
        case .icd10pcs: return .teal; case .hcpcs: return .orange; case .none: return .gray
        }
    }
}

// ═══════════════════════════════════════════════════
// MARK: - TipItem (used elsewhere)
// ═══════════════════════════════════════════════════

struct TipItem: View {
    let icon: String; let text: String
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundColor(.accentColor).frame(width: 24)
            Text(text).font(.subheadline).foregroundColor(.secondary)
        }
    }
}

// ═══════════════════════════════════════════════════
// MARK: - ScannedCodeRow (used by HomeView)
// ═══════════════════════════════════════════════════

struct ScannedCodeRow: View {
    let scannedCode: ScannedCode
    let onTap: () -> Void
    let onSave: () -> Void
    let isSaved: Bool
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(scannedCode.displayType)
                .font(.caption2).fontWeight(.bold).foregroundColor(.white)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(typeColor).cornerRadius(6)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(scannedCode.detectedCode).font(.headline).fontWeight(.semibold)
                if scannedCode.isLookingUp {
                    HStack(spacing: 6) { ProgressView().scaleEffect(0.7); Text("Looking up…").font(.caption).foregroundColor(.secondary) }
                } else if let mc = scannedCode.matchedMedicalCode {
                    Text(mc.shortDescription).font(.subheadline).foregroundColor(.secondary).lineLimit(2)
                    if mc.hasValidPricing { Text(mc.formattedPriceRange).font(.caption).foregroundColor(.green).fontWeight(.medium) }
                } else {
                    if !scannedCode.scannedDescription.isEmpty {
                        Text(scannedCode.scannedDescription).font(.subheadline).foregroundColor(.secondary).lineLimit(2).italic()
                    }
                    if scannedCode.lookupFailed { Text("Not in database").font(.caption).foregroundColor(.orange) }
                }
                if let p = scannedCode.scannedPrice, p > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "dollarsign.circle.fill").font(.caption2).foregroundColor(.orange)
                        Text(p, format: .currency(code: "USD")).font(.caption).fontWeight(.medium)
                    }
                }
            }
            Spacer()
            VStack(spacing: 8) {
                Button { onSave() } label: {
                    Image(systemName: isSaved ? "star.fill" : "star").foregroundColor(isSaved ? .yellow : .gray)
                }.buttonStyle(.plain)
                if scannedCode.matchedMedicalCode != nil {
                    Image(systemName: "chevron.right").font(.caption).foregroundColor(Color(.tertiaryLabel))
                }
            }
        }
        .padding(.vertical, 4).contentShape(Rectangle())
        .onTapGesture { if scannedCode.matchedMedicalCode != nil { onTap() } }
    }
    
    private var typeColor: Color {
        switch scannedCode.possibleType {
        case .cpt: return .blue; case .icd10: return .green
        case .icd10pcs: return .teal; case .hcpcs: return .orange; case .none: return .gray
        }
    }
}

// ═══════════════════════════════════════════════════
// MARK: - Comparable Clamp Extension
// ═══════════════════════════════════════════════════

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

// ═══════════════════════════════════════════════════
// MARK: - Add Codes to Database
// (inlined here to avoid separate target membership)
// ═══════════════════════════════════════════════════

private struct DBCodeEntry: Identifiable {
    let id: UUID
    var code:        String
    var description: String
    var price:       String
    var codeType:    MedicalCodeType?
    var alreadyExists: Bool
    var selected:    Bool

    init(from scanned: ScannedCode, exists: Bool) {
        id            = scanned.id
        code          = scanned.detectedCode
        description   = scanned.bestDescription
        price         = scanned.scannedPrice.map { String(format: "%.2f", $0) } ?? ""
        codeType      = scanned.possibleType
        alreadyExists = exists
        selected      = !exists
    }
}

struct CustomMedicalCode: Codable, Identifiable {
    var id:          UUID   = UUID()
    var code:        String
    var description: String
    var codeType:    String
    var price:       Double?
    var dateAdded:   Date
}

struct AddCodesToDatabaseView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let codes: [ScannedCode]

    @State private var entries:       [DBCodeEntry] = []
    @State private var isSaving      = false
    @State private var savedCount    = 0
    @State private var showDoneAlert = false

    private let storageKey = "UserAddedMedicalCodes_v1"

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.black)
                        Text("Review codes before adding. Existing codes are pre-deselected and will NOT be overwritten.")
                            .font(.caption).foregroundColor(.black)
                    }
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.yellow.opacity(0.85)).cornerRadius(8)
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 4, trailing: 12))
                    .listRowBackground(Color.clear)
                }

                Section {
                    ForEach($entries) { $entry in DBCodeEntryRow(entry: $entry) }
                } header: {
                    HStack {
                        Label("Codes to Add", systemImage: "barcode.viewfinder")
                        Spacer()
                        Text("\(entries.filter(\.selected).count) selected")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }

                Section {
                    Button {
                        let hasUnselected = entries.contains { !$0.selected && !$0.alreadyExists }
                        for i in entries.indices where !entries[i].alreadyExists {
                            entries[i].selected = hasUnselected
                        }
                    } label: {
                        let allNew      = entries.filter { !$0.alreadyExists }
                        let allSelected = allNew.allSatisfy(\.selected)
                        Label(allSelected ? "Deselect All New" : "Select All New",
                              systemImage: allSelected ? "circle" : "checkmark.circle")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Add to Database")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView().progressViewStyle(.circular)
                    } else {
                        Button { saveSelected() } label: {
                            Text("Save \(entries.filter(\.selected).count)").fontWeight(.semibold)
                                .foregroundColor(entries.filter(\.selected).isEmpty ? .secondary : .yellow)
                        }
                        .disabled(entries.filter(\.selected).isEmpty)
                    }
                }
            }
            .alert("Codes Added", isPresented: $showDoneAlert) {
                Button("Done") { dismiss() }
            } message: {
                Text("\(savedCount) code\(savedCount == 1 ? "" : "s") added to the database.")
            }
            .onAppear { buildEntries() }
        }
    }

    private func buildEntries() {
        let existing    = loadCustomCodes()
        let existingSet = Set(existing.map { $0.code.uppercased() })
        let builtInSet  = Set(appState.cloudKitService.allCodes.map { $0.code.uppercased() })
        entries = codes.map { scanned in
            let up = scanned.detectedCode.uppercased()
            return DBCodeEntry(from: scanned, exists: existingSet.contains(up) || builtInSet.contains(up))
        }
    }

    private func saveSelected() {
        isSaving = true
        var existing    = loadCustomCodes()
        let existingSet = Set(existing.map { $0.code.uppercased() })
        var added = 0
        for entry in entries where entry.selected && !entry.alreadyExists {
            guard !existingSet.contains(entry.code.uppercased()), !entry.code.isEmpty else { continue }
            let price = Double(entry.price.replacingOccurrences(of: "$", with: "")
                                         .replacingOccurrences(of: ",", with: ""))
            existing.append(CustomMedicalCode(
                code: entry.code, description: entry.description,
                codeType: entry.codeType?.rawValue ?? "Unknown",
                price: price, dateAdded: Date()))
            added += 1
        }
        persistCustomCodes(existing)
        savedCount = added; isSaving = false; showDoneAlert = true
    }

    private func loadCustomCodes() -> [CustomMedicalCode] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([CustomMedicalCode].self, from: data)
        else { return [] }
        return decoded
    }

    private func persistCustomCodes(_ codes: [CustomMedicalCode]) {
        guard let data = try? JSONEncoder().encode(codes) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}

private struct DBCodeEntryRow: View {
    @Binding var entry: DBCodeEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Button {
                    if !entry.alreadyExists { entry.selected.toggle() }
                } label: {
                    Image(systemName: entry.selected ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(entry.alreadyExists ? .secondary : (entry.selected ? .yellow : .secondary))
                        .font(.title3)
                }.buttonStyle(.plain)

                Text(entry.code)
                    .font(.system(.subheadline, design: .monospaced)).fontWeight(.bold)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(codeColor.opacity(0.15)).foregroundColor(codeColor).cornerRadius(6)

                Spacer()

                if entry.alreadyExists {
                    Label("Exists", systemImage: "checkmark.seal.fill")
                        .font(.caption2).foregroundColor(.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(Color(.tertiarySystemBackground)).cornerRadius(6)
                }
            }
            TextField("Description", text: $entry.description)
                .font(.subheadline)
                .foregroundColor(entry.alreadyExists ? .secondary : .primary)
                .disabled(entry.alreadyExists)
            HStack(spacing: 6) {
                Image(systemName: "dollarsign.circle").font(.caption).foregroundColor(.secondary)
                TextField("Price (optional)", text: $entry.price)
                    .font(.caption).keyboardType(.decimalPad)
                    .foregroundColor(entry.alreadyExists ? .secondary : .primary)
                    .disabled(entry.alreadyExists)
            }
        }
        .padding(.vertical, 4).opacity(entry.alreadyExists ? 0.55 : 1.0)
    }

    private var codeColor: Color {
        switch entry.codeType {
        case .cpt: return .blue; case .hcpcs: return .purple
        case .icd10: return .orange; default: return .secondary
        }
    }
}

#Preview {
    ScannerView()
        .environmentObject(AppState())
}
