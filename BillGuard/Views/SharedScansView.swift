//
//  SharedScansView.swift
//  BillGuard
//
//  Bills saved from the share extension: the `MedicalBillScan` records in the
//  private CloudKit database, listed for review. A scan can be added to a
//  patient's bills or deleted. Compiled into both the iOS app and the Mac app
//  (see BillGuardMac/project.yml); each app supplies its own bill review screen.
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
    var status: String
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

    /// `status` once the scan has been added to a patient's bills. The share
    /// extension saves every scan as "PendingReview".
    static let importedStatus = "Imported"
    var isImported: Bool { status == Self.importedStatus }

    var statusLabel: String {
        switch status {
        case "PendingReview": return "Pending review"
        case Self.importedStatus: return "Added to Bills"
        default: return status
        }
    }

    /// Every page's text, in page order.
    var fullText: String { pages.map(\.rawText).joined(separator: "\n") }
    /// The provider's name and address from the top of the first page, if any.
    var letterhead: String { BillCodeAnalyzer.letterhead(in: pages.first?.rawText ?? "") }
    /// The patient and insurance details printed with a label.
    var labelledFields: BillCodeAnalyzer.LabelledFields { BillCodeAnalyzer.labelledFields(in: fullText) }
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

    /// Scans that have not been added to a patient's bills yet.
    var pendingCount: Int { scans.filter { !$0.isImported }.count }

    /// A store with fixed contents never talks to iCloud (previews).
    private let isFixed: Bool
    private var isRefreshing = false
    /// Deletes in flight, so a refresh that started earlier cannot bring them back.
    private var deletingIDs: Set<String> = []

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
            scans = fetched.filter { !deletingIDs.contains($0.id) }
                .sorted { $0.scannedAt > $1.scannedAt }
            status = .loaded
        case .noAccount:
            scans = []
            status = .noAccount
        case .failed(let message):
            status = .failed(message)
        }
    }

    /// Removes the scan from iCloud, on every device. Returns a message when
    /// it could not be deleted; the scan is then put back in the list.
    func delete(_ scan: SharedScan) async -> String? {
        guard let index = scans.firstIndex(where: { $0.id == scan.id }) else { return nil }
        let removed = scans.remove(at: index)
        guard !isFixed else { return nil }
        deletingIDs.insert(scan.id)
        defer { deletingIDs.remove(scan.id) }
        do {
            try await Self.deleteRecord(named: scan.id)
            return nil
        } catch {
            if !scans.contains(where: { $0.id == removed.id }) {
                scans.append(removed)
                scans.sort { $0.scannedAt > $1.scannedAt }
            }
            return Self.message(for: error)
        }
    }

    /// Records that the scan was added to a patient's bills. Returns a message
    /// when iCloud could not be updated; the scan then stays pending.
    func markImported(_ scan: SharedScan) async -> String? {
        guard !isFixed else {
            setStatus(SharedScan.importedStatus, of: scan.id)
            return nil
        }
        do {
            try await Self.saveStatus(SharedScan.importedStatus, recordNamed: scan.id)
            setStatus(SharedScan.importedStatus, of: scan.id)
            return nil
        } catch {
            return Self.message(for: error)
        }
    }

    private func setStatus(_ status: String, of id: String) {
        guard let index = scans.firstIndex(where: { $0.id == id }) else { return }
        scans[index].status = status
    }

    nonisolated private static func deleteRecord(named name: String) async throws {
        let database = CKContainer(identifier: SharedScan.containerID).privateCloudDatabase
        do {
            _ = try await database.deleteRecord(withID: CKRecord.ID(recordName: name))
        } catch let error as CKError where error.code == .unknownItem {
            // Already deleted on another device.
        }
    }

    nonisolated private static func saveStatus(_ status: String, recordNamed name: String) async throws {
        let database = CKContainer(identifier: SharedScan.containerID).privateCloudDatabase
        let record = try await database.record(for: CKRecord.ID(recordName: name))
        record["status"] = status
        _ = try await database.save(record)
    }

    nonisolated private static func message(for error: Error) -> String {
        if let error = error as? CKError {
            switch error.code {
            case .notAuthenticated:
                return "Sign in to iCloud on this device and try again."
            case .networkUnavailable, .networkFailure:
                return "iCloud can't be reached right now. Check your connection and try again."
            default:
                break
            }
        }
        return error.localizedDescription
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
    /// Builds the app's own bill review screen for a scan. That screen calls
    /// `finish` with true once the bill is saved, or false if it is cancelled.
    typealias ImportScreen = (SharedScan, _ finish: @escaping (_ saved: Bool) -> Void) -> AnyView

    private let title: String
    /// A plain-language description for a code, when the app's database has one.
    private let describe: (String) -> String?
    /// Without one, scans can be read and deleted but not added to Bills.
    private let importScreen: ImportScreen?
    /// Set when the list is shown in a sheet, to add a Done button.
    private let onDone: (() -> Void)?
    @ObservedObject private var store: SharedScanStore
    /// The scan a delete confirmation is showing for (list rows).
    @State private var pendingDelete: SharedScan?
    @State private var problem: Problem?
    #if os(macOS)
    @State private var sheet: MacSheet?
    @State private var confirmingSheetDelete = false
    #else
    @State private var path: [SharedScan.ID] = []
    @State private var importing: SharedScan?
    #endif

    private struct Problem: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    #if os(macOS)
    /// One sheet at a time: going from a scan to its bill review swaps them.
    private enum MacSheet: Identifiable {
        case detail(SharedScan)
        case importing(SharedScan)

        var id: String {
            switch self {
            case .detail(let scan): return "detail-" + scan.id
            case .importing(let scan): return "import-" + scan.id
            }
        }
    }
    #endif

    init(title: String = "Shared Scans",
         store: SharedScanStore? = nil,
         describe: @escaping (String) -> String? = { _ in nil },
         importScreen: ImportScreen? = nil,
         onDone: (() -> Void)? = nil) {
        self.title = title
        self.store = store ?? .shared
        self.describe = describe
        self.importScreen = importScreen
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
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .detail(let scan):
                detailSheet(scan)
            case .importing(let scan):
                importScreen?(scan) { saved in finishImport(scan, saved: saved) }
            }
        }
        .modifier(problemAlert)
        .task { await store.refresh() }
        #else
        NavigationStack(path: $path) {
            content
                .sharedScanTitle(title)
                .navigationDestination(for: SharedScan.ID.self) { id in
                    if let scan = store.scans.first(where: { $0.id == id }) {
                        SharedScanDetailView(
                            scan: scan, describe: describe,
                            onImport: importScreen == nil ? nil : { startImport(scan) },
                            onDelete: { delete(scan) })
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
        .sheet(item: $importing) { scan in
            importScreen?(scan) { saved in finishImport(scan, saved: saved) }
        }
        .modifier(problemAlert)
        #endif
    }

    // MARK: Actions

    static let deleteTitle = "Delete this scan?"
    static let deleteMessage = "It is removed from iCloud on all your devices. Bills already added from it are kept."

    static func importLabel(for scan: SharedScan) -> String {
        scan.isImported ? "Add to Bills Again" : "Add to Bills"
    }

    /// The alert for anything iCloud refused.
    private var problemAlert: some ViewModifier {
        ProblemAlert(title: problem?.title ?? "",
                     message: problem?.message ?? "",
                     isPresented: Binding(get: { problem != nil },
                                          set: { if !$0 { problem = nil } }))
    }

    private struct ProblemAlert: ViewModifier {
        let title: String
        let message: String
        @Binding var isPresented: Bool

        func body(content: Content) -> some View {
            content.alert(title, isPresented: $isPresented) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(message)
            }
        }
    }

    /// The delete confirmation for a list row, attached to the row so that it
    /// appears beside it.
    private func isConfirmingDelete(of scan: SharedScan) -> Binding<Bool> {
        Binding(get: { pendingDelete?.id == scan.id },
                set: { if !$0, pendingDelete?.id == scan.id { pendingDelete = nil } })
    }

    private func startImport(_ scan: SharedScan) {
        #if os(macOS)
        sheet = .importing(scan)
        #else
        importing = scan
        #endif
    }

    /// Called by the app's bill review screen. May be called more than once.
    private func finishImport(_ scan: SharedScan, saved: Bool) {
        #if os(macOS)
        sheet = nil
        #else
        importing = nil
        #endif
        guard saved, store.scans.first(where: { $0.id == scan.id })?.isImported != true else { return }
        Task {
            if let message = await store.markImported(scan) {
                problem = Problem(
                    title: "Bill Added",
                    message: "The bill was saved, but this scan could not be marked as added, so it still shows as pending. \(message)")
            }
        }
    }

    private func delete(_ scan: SharedScan) {
        Task {
            #if os(macOS)
            sheet = nil
            #else
            if path.contains(scan.id) {
                // Leave the scan's screen before its contents go away.
                path.removeAll { $0 == scan.id }
                try? await Task.sleep(for: .milliseconds(450))
            }
            #endif
            if let message = await store.delete(scan) {
                problem = Problem(title: "Couldn't Delete Scan", message: message)
            }
        }
    }

    @ViewBuilder private func rowMenu(_ scan: SharedScan) -> some View {
        if importScreen != nil {
            Button { startImport(scan) } label: {
                Label(Self.importLabel(for: scan), systemImage: "doc.badge.plus")
            }
        }
        Button(role: .destructive) { pendingDelete = scan } label: {
            Label("Delete…", systemImage: "trash")
        }
    }

    #if os(macOS)
    private func detailSheet(_ scan: SharedScan) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(scan.title).font(.headline).lineLimit(1)
                Spacer()
                Button(role: .destructive) { confirmingSheetDelete = true } label: {
                    Label("Delete", systemImage: "trash")
                }
                if importScreen != nil {
                    Button { startImport(scan) } label: {
                        Label(Self.importLabel(for: scan) + "…", systemImage: "doc.badge.plus")
                    }
                }
                Button("Done") { sheet = nil }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(14)
            .background(Color("BrandNavy"))
            SharedScanDetailView(scan: scan, describe: describe)
        }
        .frame(minWidth: 520, idealWidth: 560, minHeight: 560, idealHeight: 640)
        .confirmationDialog(Self.deleteTitle, isPresented: $confirmingSheetDelete, titleVisibility: .visible) {
            Button("Delete Scan", role: .destructive) { delete(scan) }
        } message: {
            Text(Self.deleteMessage)
        }
    }
    #endif

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
        Button { sheet = .detail(scan) } label: {
            SharedScanRow(scan: scan).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu { rowMenu(scan) }
        .confirmationDialog(Self.deleteTitle, isPresented: isConfirmingDelete(of: scan), titleVisibility: .visible) {
            Button("Delete Scan", role: .destructive) { delete(scan) }
        } message: {
            Text(Self.deleteMessage)
        }
        #else
        NavigationLink(value: scan.id) { SharedScanRow(scan: scan) }
            .contextMenu { rowMenu(scan) }
            .confirmationDialog(Self.deleteTitle, isPresented: isConfirmingDelete(of: scan), titleVisibility: .visible) {
                Button("Delete Scan", role: .destructive) { delete(scan) }
            } message: {
                Text(Self.deleteMessage)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                // Not a destructive-role button: the row stays until confirmed.
                Button { pendingDelete = scan } label: {
                    Label("Delete", systemImage: "trash")
                }
                .tint(.red)
            }
            .swipeActions(edge: .leading) {
                if importScreen != nil {
                    Button { startImport(scan) } label: {
                        Label("Add to Bills", systemImage: "doc.badge.plus")
                    }
                    .tint(Color("BrandTeal"))
                }
            }
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
                if scan.isImported {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Added to Bills")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
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
    /// Set to show the actions in the list (iPhone). The Mac puts them in the
    /// sheet's title bar instead.
    var onImport: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    @State private var confirmingDelete = false

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

            if onImport != nil || onDelete != nil {
                Section {
                    if let onImport {
                        Button(action: onImport) {
                            actionLabel(SharedScansView.importLabel(for: scan), systemImage: "doc.badge.plus")
                        }
                    }
                    if let onDelete {
                        Button(role: .destructive) { confirmingDelete = true } label: {
                            actionLabel("Delete Scan", systemImage: "trash")
                        }
                        .confirmationDialog(SharedScansView.deleteTitle, isPresented: $confirmingDelete,
                                            titleVisibility: .visible) {
                            Button("Delete Scan", role: .destructive, action: onDelete)
                        } message: {
                            Text(SharedScansView.deleteMessage)
                        }
                    }
                } footer: {
                    if onImport != nil {
                        Text(scan.isImported
                             ? "This scan is already in Bills. Deleting it here keeps the bill."
                             : "Add to Bills opens this scan as a bill, so you can check it and save it for a patient.")
                    }
                }
                .listRowBackground(Color("BrandNavy"))
            }

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

    private func actionLabel(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage).frame(width: 22)
            Text(title)
        }
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

// MARK: - Adding a scan to Bills (iPhone)

#if os(iOS)
/// The iPhone app's bill review screen, opened on a saved scan. The charges
/// and totals are read from the scan's text the same way as a camera scan;
/// patient and insurance details come from the labelled lines only.
struct SharedScanBillReview: View {
    let scan: SharedScan
    let finish: (_ saved: Bool) -> Void
    @State private var saveResult: BillSaveResult = .none

    var body: some View {
        BillReviewView(
            patientText: "",
            providerText: scan.letterhead,
            insuranceText: "",
            procedureText: scan.fullText,
            scannedImage: nil,
            pageCount: scan.pages.count,
            saveResult: $saveResult,
            prefill: scan.labelledFields)
            .onChange(of: saveResult) { _, result in
                if result != .none { finish(true) }
            }
    }
}

extension SharedScansView {
    /// The iPhone app's Shared Scans sheet: code descriptions from the app's
    /// database, and Add to Bills through the app's bill review screen.
    init(appState: AppState, patientDataService: PatientDataService, onDone: @escaping () -> Void) {
        self.init(
            describe: { appState.cloudKitService.lookupCode($0)?.shortDescription },
            importScreen: { scan, finish in
                AnyView(SharedScanBillReview(scan: scan, finish: finish)
                    .environmentObject(patientDataService)
                    .environmentObject(appState))
            },
            onDone: onDone)
    }
}
#endif

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
                MedicalBillPage(pageNumber: 1, rawText: """
                                Riverside Medical Center
                                1200 Health Parkway
                                Springfield, IL 62704
                                Patient: Jordan Avery
                                Account #: 48213377
                                Date of Service: 09/18/2026
                                Insurance: Blue Cross Blue Shield
                                Member ID: XJK48213377
                                DX: E11.65
                                99214 Office visit  $185.00
                                80053 Metabolic panel  $95.00
                                """,
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
            status: SharedScan.importedStatus,
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
