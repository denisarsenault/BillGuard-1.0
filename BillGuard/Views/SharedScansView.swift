//
//  SharedScansView.swift
//  BillGuard
//
//  Bills saved from the share extension: the `MedicalBillScan` records in the
//  private CloudKit database, listed for review. Read-only. Compiled into both
//  the iOS app and the Mac app (see BillGuardMac/project.yml).
//

import SwiftUI
import CloudKit

// MARK: - Model

/// One saved scan, decoded from a `MedicalBillScan` record written by the
/// share extension's `CloudKitManager`.
struct SharedScan: Identifiable, Equatable, Sendable {
    static let recordType = "MedicalBillScan"
    static let containerID = "iCloud.com.billguard.BillGuard"

    let id: String              // record name
    let scannedAt: Date
    let sourceURL: String?
    let status: String
    let pages: [MedicalBillPage]
    /// Recomputed from the pages, so it always matches what is shown.
    let conflicts: [BillCodeAnalyzer.Anomaly]

    init(id: String, scannedAt: Date, sourceURL: String?, status: String, pages: [MedicalBillPage]) {
        self.id = id
        self.scannedAt = scannedAt
        self.sourceURL = sourceURL
        self.status = status
        self.pages = pages.sorted { $0.pageNumber < $1.pageNumber }
        self.conflicts = BillCodeAnalyzer.crossPageAnomalies(in: self.pages)
    }

    init?(record: CKRecord) {
        guard record.recordType == Self.recordType else { return nil }
        let json = record["pageStructureJSON"] as? String ?? "[]"
        guard let pages = try? JSONDecoder().decode([MedicalBillPage].self, from: Data(json.utf8)) else { return nil }
        let source = (record["sourceURL"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        self.init(id: record.recordID.recordName,
                  scannedAt: record["scannedAt"] as? Date ?? record.creationDate ?? .distantPast,
                  sourceURL: source,
                  status: record["status"] as? String ?? "PendingReview",
                  pages: pages)
    }

    /// The web page the bill was shared from, when it came from a browser.
    var webURL: URL? {
        guard let sourceURL, let url = URL(string: sourceURL),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              url.host != nil else { return nil }
        return url
    }

    /// Short name for the row: the site, the file name, or a generic label.
    var title: String {
        if let host = webURL?.host { return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host }
        if let sourceURL, let url = URL(string: sourceURL), url.isFileURL, !url.lastPathComponent.isEmpty {
            return url.lastPathComponent
        }
        return "Shared bill"
    }

    var statusLabel: String { status == "PendingReview" ? "Pending review" : status }
    var diagnosisCount: Int { Set(pages.flatMap(\.identifiedDiagnosticCodes)).count }
    var procedureCount: Int { Set(pages.flatMap(\.identifiedProcedureCodes)).count }
}

// MARK: - Store

/// Loads the saved scans from iCloud. Nothing is cached on the device: without
/// an iCloud account, or offline, the list says so instead.
@MainActor
final class SharedScanStore: ObservableObject {
    static let shared = SharedScanStore()

    enum Status: Equatable {
        case idle, loading, loaded, noAccount
        case failed(String)
    }

    @Published private(set) var scans: [SharedScan] = []
    @Published private(set) var status: Status = .idle

    /// A store with fixed contents never talks to iCloud (previews).
    private let isFixed: Bool
    private var isRefreshing = false

    init() { isFixed = false }

    init(fixedScans: [SharedScan], status: Status = .loaded) {
        isFixed = true
        scans = fixedScans
        self.status = status
    }

    func refresh() async {
        guard !isFixed, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        if scans.isEmpty { status = .loading }

        switch await Self.fetch() {
        case .scans(let fetched):
            scans = fetched.sorted { $0.scannedAt > $1.scannedAt }
            status = .loaded
        case .noAccount:
            scans = []
            status = .noAccount
        case .failed(let message):
            status = .failed(message)
        }
    }

    private enum FetchResult: Sendable {
        case scans([SharedScan])
        case noAccount
        case failed(String)
    }

    /// Same query style as the rest of the app's sync (see docs/CLOUDKIT_SETUP.md):
    /// it needs `recordName` marked Queryable on the record type.
    nonisolated private static func fetch() async -> FetchResult {
        let container = CKContainer(identifier: SharedScan.containerID)
        do {
            guard try await container.accountStatus() == .available else { return .noAccount }
            let database = container.privateCloudDatabase
            let query = CKQuery(recordType: SharedScan.recordType, predicate: NSPredicate(value: true))
            var scans: [SharedScan] = []
            var (results, cursor) = try await database.records(matching: query)
            while true {
                scans += results.compactMap { _, result in
                    (try? result.get()).flatMap(SharedScan.init(record:))
                }
                guard let next = cursor else { break }
                (results, cursor) = try await database.records(continuingMatchFrom: next)
            }
            return .scans(scans)
        } catch let error as CKError where error.code == .unknownItem {
            // The record type does not exist until the first scan is saved.
            return .scans([])
        } catch let error as CKError where error.code == .notAuthenticated {
            return .noAccount
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}

// MARK: - List

struct SharedScansView: View {
    private let title: String
    /// A plain-language description for a code, when the app's database has one.
    private let describe: (String) -> String?
    /// Set when the list is shown in a sheet, to add a Done button.
    private let onDone: (() -> Void)?
    @ObservedObject private var store: SharedScanStore
    #if os(macOS)
    @State private var selected: SharedScan?
    #endif

    init(title: String = "Shared Scans",
         store: SharedScanStore? = nil,
         describe: @escaping (String) -> String? = { _ in nil },
         onDone: (() -> Void)? = nil) {
        self.title = title
        self.store = store ?? .shared
        self.describe = describe
        self.onDone = onDone
    }

    var body: some View {
        #if os(macOS)
        // Like the Mac app's other screens: branded header, detail in a sheet.
        VStack(spacing: 0) {
            BrandHeader(title: title, subtitle: subtitle)
                .overlay(alignment: .trailing) {
                    Button { Task { await store.refresh() } } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(store.status == .loading)
                    .padding(.trailing, 16)
                }
            content
        }
        .brandScreen()
        .navigationTitle(title)
        .sheet(item: $selected) { scan in
            VStack(spacing: 0) {
                HStack {
                    Text(scan.title).font(.headline)
                    Spacer()
                    Button("Done") { selected = nil }
                        .keyboardShortcut(.defaultAction)
                }
                .padding(14)
                .background(Color("BrandNavy"))
                SharedScanDetailView(scan: scan, describe: describe)
            }
            .frame(minWidth: 520, idealWidth: 560, minHeight: 560, idealHeight: 640)
        }
        .task { await store.refresh() }
        #else
        NavigationStack {
            content
                .sharedScanTitle(title)
                .navigationDestination(for: SharedScan.ID.self) { id in
                    if let scan = store.scans.first(where: { $0.id == id }) {
                        SharedScanDetailView(scan: scan, describe: describe)
                    }
                }
                .toolbar {
                    if let onDone {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done", action: onDone)
                        }
                    }
                }
                .task { await store.refresh() }
        }
        #endif
    }

    private var listNote: String {
        if case .failed(let message) = store.status {
            return "Couldn't refresh from iCloud: \(message)"
        }
        return "Saved with BillGuard from the share menu. Codes were read from the page automatically, so check them against the bill."
    }

    private var subtitle: String? {
        store.scans.isEmpty ? nil : "\(store.scans.count) saved scan\(store.scans.count == 1 ? "" : "s")"
    }

    @ViewBuilder private func rowLink(_ scan: SharedScan) -> some View {
        #if os(macOS)
        Button { selected = scan } label: {
            SharedScanRow(scan: scan).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        #else
        NavigationLink(value: scan.id) { SharedScanRow(scan: scan) }
        #endif
    }

    @ViewBuilder private var content: some View {
        if !store.scans.isEmpty {
            List {
                Section {
                    ForEach(store.scans) { scan in
                        rowLink(scan)
                    }
                    #if os(macOS)
                    SharedScanNote(text: listNote)
                    #endif
                } footer: {
                    #if !os(macOS)
                    Text(listNote)
                    #endif
                }
                .listRowBackground(Color("BrandNavy"))
            }
            .sharedScanListStyle()
            .refreshable { await store.refresh() }
        } else {
            emptyState
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color("BrandDeepNavy").ignoresSafeArea())
        }
    }

    @ViewBuilder private var emptyState: some View {
        switch store.status {
        case .idle, .loading:
            ProgressView("Loading from iCloud…")
        case .noAccount:
            ContentUnavailableView(
                "iCloud Is Off",
                systemImage: "icloud.slash",
                description: Text("Sign in to iCloud on this device to see the bills you saved from the share menu."))
        case .failed(let message):
            ContentUnavailableView {
                Label("Couldn't Load Scans", systemImage: "exclamationmark.icloud")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") { Task { await store.refresh() } }
            }
        case .loaded:
            ContentUnavailableView(
                "No Shared Scans",
                systemImage: "square.and.arrow.up",
                description: Text("Open a bill in your browser or in Files, choose Share, then BillGuard. Bills you save there appear here."))
        }
    }
}

private extension View {
    /// The app's dark navy surfaces behind a list, on either platform.
    func sharedScanListStyle() -> some View {
        scrollContentBackground(.hidden)
            .background(Color("BrandDeepNavy").ignoresSafeArea())
    }

    /// An inline title in the brand gradient, as the app's own toolbar draws it
    /// (iOS). On the Mac the title is the screen's header instead.
    @ViewBuilder func sharedScanTitle(_ title: String) -> some View {
        #if os(iOS)
        navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(title)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .foregroundStyle(LinearGradient(colors: [Color("BrandCyan"), Color("BrandTeal")],
                                                        startPoint: .leading, endPoint: .trailing))
                }
            }
        #else
        navigationTitle(title)
        #endif
    }
}

#if os(macOS)
/// A Mac list footer is clipped to one line, so notes there are rows instead.
private struct SharedScanNote: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
#endif

private struct SharedScanRow: View {
    let scan: SharedScan

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text.viewfinder")
                .font(.title3)
                .foregroundStyle(Color("BrandCyan"))
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(scan.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text("\(scan.scannedAt.formatted(date: .abbreviated, time: .shortened)) · \(scan.pages.count) page\(scan.pages.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !scan.conflicts.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text("\(scan.conflicts.count) conflict\(scan.conflicts.count == 1 ? "" : "s") to review")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                SharedScanCountChip(count: scan.diagnosisCount, label: "DX", color: .green)
                SharedScanCountChip(count: scan.procedureCount, label: "PX", color: Color("BrandCyan"))
            }
        }
        .padding(.vertical, 2)
    }
}

private struct SharedScanCountChip: View {
    let count: Int
    let label: String
    let color: Color

    var body: some View {
        Text("\(count) \(label)")
            .font(.caption.weight(.semibold))
            .monospacedDigit()
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
            .accessibilityLabel("\(count) \(label == "DX" ? "diagnosis" : "procedure") code\(count == 1 ? "" : "s")")
    }
}

// MARK: - Detail

struct SharedScanDetailView: View {
    let scan: SharedScan
    var describe: (String) -> String? = { _ in nil }

    var body: some View {
        List {
            Section("Scan") {
                LabeledContent("Scanned", value: scan.scannedAt.formatted(date: .abbreviated, time: .shortened))
                if let url = scan.webURL {
                    LabeledContent("Source") { Link(scan.title, destination: url) }
                } else if scan.sourceURL != nil {
                    LabeledContent("Source", value: scan.title)
                }
                LabeledContent("Pages", value: "\(scan.pages.count)")
                LabeledContent("Status", value: scan.statusLabel)
            }
            .listRowBackground(Color("BrandNavy"))

            if !scan.conflicts.isEmpty {
                Section {
                    ForEach(scan.conflicts) { conflict in
                        conflictRow(conflict)
                    }
                    #if os(macOS)
                    SharedScanNote(text: Self.conflictNote)
                    #endif
                } header: {
                    HStack(spacing: 5) {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text("Cross-Page Conflicts")
                    }
                    .foregroundStyle(.red)
                } footer: {
                    #if !os(macOS)
                    Text(Self.conflictNote)
                    #endif
                }
                .listRowBackground(Color("BrandNavy"))
            }

            ForEach(scan.pages) { page in
                Section("Page \(page.pageNumber)") {
                    if page.identifiedDiagnosticCodes.isEmpty && page.identifiedProcedureCodes.isEmpty {
                        Text("No codes found on this page.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(page.identifiedDiagnosticCodes, id: \.self) { code in
                        codeRow(code, kind: "Diagnosis code", color: .green, repeated: false)
                    }
                    ForEach(page.identifiedProcedureCodes, id: \.self) { code in
                        codeRow(code, kind: "Procedure code", color: Color("BrandCyan"),
                                repeated: page.overlappingCodes.contains(code))
                    }
                    if !page.rawText.isEmpty {
                        DisclosureGroup("Scanned text") {
                            Text(page.rawText)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .listRowBackground(Color("BrandNavy"))
            }
        }
        .sharedScanListStyle()
        .sharedScanTitle(scan.title)
    }

    private static let conflictNote = "The same code on more than one page can mean a duplicate charge. Compare the dates and amounts on the bill."

    private func codeChip(_ code: String, color: Color) -> some View {
        Text(code)
            .font(.system(.subheadline, design: .monospaced).bold())
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(color.opacity(0.18), in: RoundedRectangle(cornerRadius: 5))
            .foregroundStyle(color)
    }

    private func codeRow(_ code: String, kind: String, color: Color, repeated: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            codeChip(code, color: color)
            VStack(alignment: .leading, spacing: 2) {
                Text(describe(code) ?? kind)
                    .font(.subheadline)
                if repeated {
                    Text("Billed more than once on this page")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private func conflictRow(_ conflict: BillCodeAnalyzer.Anomaly) -> some View {
        let pages = conflict.pageNumbers.map(String.init).joined(separator: ", ")
        let isProcedure = conflict.kind == .duplicateProcedure
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            codeChip(conflict.code, color: isProcedure ? Color("BrandCyan") : .green)
            Text(isProcedure
                 ? "Procedure code billed on pages \(pages)"
                 : "Diagnosis on pages \(pages), with no procedure code on at least one of them")
                .font(.subheadline)
        }
    }
}

// MARK: - Preview

#if DEBUG
extension SharedScan {
    static let previewSamples: [SharedScan] = [
        SharedScan(
            id: "sample-1",
            scannedAt: Date(timeIntervalSince1970: 1_795_000_000),
            sourceURL: "https://www.examplehealth.org/billing/statement",
            status: "PendingReview",
            pages: [
                MedicalBillPage(pageNumber: 1, rawText: "99214 Office visit  $185.00\n80053 Metabolic panel  $95.00",
                                identifiedDiagnosticCodes: ["E11.65"], identifiedProcedureCodes: ["99214", "80053"],
                                overlappingCodes: []),
                MedicalBillPage(pageNumber: 2, rawText: "99214 Office visit  $185.00\nJ1885 Ketorolac  $42.00\nJ1885 Ketorolac  $42.00",
                                identifiedDiagnosticCodes: [], identifiedProcedureCodes: ["99214", "J1885"],
                                overlappingCodes: ["J1885"]),
            ]),
        SharedScan(
            id: "sample-2",
            scannedAt: Date(timeIntervalSince1970: 1_794_600_000),
            sourceURL: nil,
            status: "PendingReview",
            pages: [
                MedicalBillPage(pageNumber: 1, rawText: "93976 Duplex scan  $412.00",
                                identifiedDiagnosticCodes: ["I70.213"], identifiedProcedureCodes: ["93976"],
                                overlappingCodes: []),
            ]),
    ]
}

#Preview("Shared scans") {
    SharedScansView(store: SharedScanStore(fixedScans: SharedScan.previewSamples))
        .preferredColorScheme(.dark)
}
#endif
