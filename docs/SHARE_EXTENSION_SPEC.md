<!--
  Source of truth for the iOS Share Extension (multi-page medical bill OCR scanner).
  Provided by Denis on 2026-11-10 and saved verbatim. The pasted copy was cut off
  partway through section 6 (inside `uploadCompleteBill`), marked at the end.
-->

> **Decisions confirmed by Denis on 2026-11-10 (these override the text below):**
> - "Billboard" is BillGuard. Real identifiers: App Group
>   `group.com.mybrightzone.BillGuard`, CloudKit container
>   `iCloud.com.billguard.BillGuard`, extension bundle
>   `com.mybrightzone.BillGuard.Share`.
> - Capture is **one share per page**, not scroll-and-append: a Share Extension
>   only receives the items shared when it opens. Each share appends its page to
>   a pending bill kept in the App Group until Commit Save or Discard.
>
> - **Procedure-code matching is tightened** (confirmed 2026-11-10). The CPT
>   regex in section 5 still finds the candidates, but a 5-digit number only
>   counts when it is in the bundled code database, is labelled as a code, or
>   sits on a line with a charge. ZIP codes, labelled identifiers (account,
>   receipt, claim…), parts of hyphenated IDs and money amounts are dropped.
> - **HCPCS codes are matched too** (2026-11-16): one letter and four digits,
>   e.g. `J1885`, under the same keep/drop rules, and never straight after a
>   diagnosis label. They go in `identifiedProcedureCodes` with the CPT codes.
> - **A modifier printed straight after a code is accepted** (2026-11-19):
>   `93976TC` and `J1885JW` are read as `93976` and `J1885`. The modifier is
>   not stored, so the same code billed with different modifiers on two pages
>   (say `TC` and `26`) still shows as a cross-page duplicate. Only modifiers
>   containing a letter count when glued on; seven digits in a row is an ID.
>   A letter-first code followed by `XA`, `XD` or `XS` (`T8111XA`) is an
>   undotted ICD-10 code, not HCPCS plus a modifier. The main app's scanners
>   follow the same rules (`ProcedureCodeEnding` in `ScannerViewModel.swift`).
> - **The extension matches the main app's look** (2026-11-16): dark only, the
>   app's asset catalog (brand colours and shield logo), cyan tint. The bar shows
>   the shield and "BillGuard" instead of the section 6 title, which did not fit.
> - **There is a macOS build as well as the iOS one** (2026-11-19). The Mac app
>   embeds `BillGuardShareMac` (bundle `com.mybrightzone.BillGuardMac.Share`),
>   compiled from the same `BillGuardShare/` sources; only the hosting controller
>   (`BillGuardMac/ShareExtension/`) differs. Two Mac-only differences: Vision
>   runs at the `.fast` level on images upscaled to 2400 px (`.accurate` takes
>   about a minute or hangs in the Mac sandbox), and pending pages are kept in
>   the extension's own Application Support folder, not an App Group, so pages
>   captured on the Mac and on the iPhone only meet once saved to CloudKit.
>
> - **Saved scans are shown in the apps** (2026-11-20), read-only: "Shared
>   Scans" on iPhone (profile menu, plus a Home banner and a Bills row when
>   there are any) and "Web Captures" in the Mac sidebar. One screen for both,
>   `BillGuard/Views/SharedScansView.swift`, reading `MedicalBillScan` records
>   straight from iCloud. `recordName` must be Queryable on that record type
>   (see `docs/CLOUDKIT_SETUP.md`).
>
> Implementation lives in `BillGuardShare/`. Overlap rules as implemented:
> a page's `overlappingCodes` are procedure codes billed more than once on that
> page; a cross-page anomaly is a procedure code on more than one page, or a
> diagnosis repeated across pages where one of them has no procedure code.

# Project Specification: Billboard iOS App Extension (Multi-Page Medical Bill OCR Scanner)

## 1. Executive Summary & Goal
We are expanding the Billboard for iOS application to include an intelligent, multi-page medical bill scanner via a single, unified iOS Share Extension. The extension targets Safari, Google Chrome, and Firefox on iOS.

Built entirely in SwiftUI, the extension uses Apple’s Vision Framework to perform local OCR on web elements, portal pages, screenshots, or inline PDFs directly inside the browser context.

### Key Custom Requirements:
* Manual Multipage Workflow: The user scrolls through the web portal or document manually and hits a dedicated "Append Page" button in the extension interface to capture subsequent segments.
* Visual Warning Banner: The extension must analyze the document text locally on a page-by-page scale to identify overlapping diagnostic (ICD-10) and procedure (CPT) codes, displaying an immediate high-risk warning banner if code anomalies or duplication patterns cross pages.
* CloudKit Storage: The parsed multi-page matrix syncs directly via a shared private CloudKit container.

## 2. Core Architecture & App Groups
To facilitate secure local document processing and background synchronization between the main iOS application and the browser extension:
* App Group Identifier: group.com.yourcompany.billboard
* CloudKit Container ID: iCloud.com.yourcompany.billboard
* Capabilities Matrix: Enable App Groups and CloudKit under Signing & Capabilities for both the main app and extension targets.

## 3. Extension Configuration (Info.plist)
Configure the extension's activation rules to process web components, text payloads, direct PDF documents, and image snapshots:

```xml
<key>NSExtension</key>
<dict>
    <key>NSExtensionAttributes</key>
    <dict>
        <key>NSExtensionActivationRule</key>
        <string>
            SUBQUERY(
                extensionItems,
                \$extensionItem,
                SUBQUERY(
                    \$extensionItem.attachments,
                    \$attachment,
                    ANY \$attachment.registeredTypeIdentifiers UTI-CONFORMS-TO "public.url"
                    OR ANY \$attachment.registeredTypeIdentifiers UTI-CONFORMS-TO "public.plain-text"
                    OR ANY \$attachment.registeredTypeIdentifiers UTI-CONFORMS-TO "com.adobe.pdf"
                    OR ANY \$attachment.registeredTypeIdentifiers UTI-CONFORMS-TO "public.image"
                ).@count > 0
            ).@count > 0
        </string>
    </dict>
    <key>NSExtensionPointIdentifier</key>
    <string>com.apple.share-services</string>
</dict>
```

## 4. Multi-Page Schema & Shared CloudKit Core
The multi-page matrix structures each page independently while tracking global cross-page structural discrepancies.

### Data Structural Models
```swift
import Foundation

public struct MedicalBillPage: Codable, Identifiable {
    public var id = UUID()
    public var pageNumber: Int
    public var rawText: String
    public var identifiedDiagnosticCodes: [String] // Regex-extracted ICD-10 codes
    public var identifiedProcedureCodes: [String]  // Regex-extracted CPT/HCPCS codes
    public var overlappingCodes: [String]          // Matches occurring within the same page context
}

public struct MedicalBillPayload: Codable {
    public var sourceURL: String?
    public var totalPages: Int
    public var pages: [MedicalBillPage]
    public var totalRiskAnomaliesFound: Int
    public var clientScannedAt: Date
}
```

### Thread-Safe CloudKit Engine
Generate an isolated CloudKitManager actor to save this structural payload securely:

```swift
import CloudKit

public actor CloudKitManager {
    public static let shared = CloudKitManager()
    private let container = CKContainer(identifier: "iCloud.com.yourcompany.billboard")
    private var privateDB: CKDatabase { container.privateCloudDatabase }
    
    public func saveMultiPageBill(payload: MedicalBillPayload) async throws {
        let record = CKRecord(recordType: "MedicalBillScan")
        record["sourceURL"] = payload.sourceURL as CKRecordValue?
        record["scannedAt"] = payload.clientScannedAt as CKRecordValue
        record["status"] = "PendingReview" as CKRecordValue
        record["anomalyCount"] = payload.totalRiskAnomaliesFound as CKRecordValue
        
        let encoder = JSONEncoder()
        if let encodedPages = try? encoder.encode(payload.pages) {
            record["pageStructureJSON"] = String(data: encodedPages, encoding: .utf8) as CKRecordValue?
        }
        
        try await privateDB.save(record)
    }
}
```

## 5. Local OCR & Code Overlap Logic
1. Vision Text Engine: Use VNRecognizeTextRequest at .accurate recognition level to process input views.
2. Regular Expressions:
   * ICD-10 (Diagnostic): \b[A-Z][0-9][0-9A-Z](?:\.[0-9A-Z]{1,4})?\b
   * CPT (Procedure): \b[0-9]{5}\b
3. Cross-Page Dynamic Overlap Rule: If an identical diagnostic code maps to conflicting billing structures across different pages (e.g., duplicated procedure codes or unlinked standalone line items), flag this as a critical overlap anomaly.

## 6. SwiftUI Extension View Architecture
This SwiftUI view includes a dynamic warning banner component and manual page multi-appending actions.

```swift
import SwiftUI

struct ExtensionContentView: View {
    var extensionContext: NSExtensionContext?
    
    @State private var billPages: [MedicalBillPage] = []
    @State private var isProcessing: Bool = false
    @State private var anomaliesDetectedCount: Int = 0
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if anomaliesDetectedCount > 0 {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.yellow)
                            Text("High-Risk Code Overlap Detected")
                                .font(.headline)
                                .foregroundColor(.white)
                        }
                        Text("We detected \(anomaliesDetectedCount) diagnostic or procedure code conflicts across your captured pages. Review these anomalies before final save.")
                            .font(.caption)
                            .foregroundColor(.white)
                    }
                    .padding()
                    .background(Color.red.opacity(0.85))
                    .cornerRadius(8)
                    .padding()
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                
                List {
                    Section("Captured Breakdown") {
                        if billPages.isEmpty {
                            Text("No sections captured yet. Scroll your browser view and hit Append Page below.")
                                .foregroundColor(.secondary)
                                .font(.subheadline)
                        } else {
                            ForEach(billPages) { page in
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text("Page \(page.pageNumber)")
                                            .font(.subheadline)
                                            .bold()
                                        Text("\(page.overlappingCodes.count) Overlaps Found")
                                            .font(.caption2)
                                            .foregroundColor(page.overlappingCodes.isEmpty ? .secondary : .red)
                                    }
                                    Spacer()
                                    Text("\(page.identifiedDiagnosticCodes.count) DX / \(page.identifiedProcedureCodes.count) PX")
                                        .font(.caption)
                                }
                            }
                        }
                    }
                    
                    Section {
                        Button(action: captureCurrentWebContextPage) {
                            Label("Capture & Append Current View", systemImage: "doc.text.viewfinder")
                        }
                        .disabled(isProcessing)
                    }
                }
            }
            .navigationTitle("Billboard Medical Scanner")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { extensionContext?.completeRequest(returningItems: nil) }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Commit Save") { Task { await uploadCompleteBill() } }
                        .disabled(billPages.isEmpty || isProcessing)
                }
            }
        }
    }
    
    private func captureCurrentWebContextPage() {
        isProcessing = true
        // Logic details implemented in target files
        isProcessing = false
    }
    
    private func uploadCompleteBill() async {
        isProcessing = true
        let payload = MedicalBillPayload(
            sourceURL: "", 
            totalPages: billPages.count,
            pages: billPages,
            totalRiskAnomaliesFound: anomaliesDetectedCount,
            clientScannedAt: Date()
        )
        do {
```

<!-- TRUNCATED: the pasted specification ended here, mid-`uploadCompleteBill`. -->
