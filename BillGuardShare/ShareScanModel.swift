//
//  ShareScanModel.swift
//  BillGuardShare
//
//  State for one share: load the pages captured so far, append what this share
//  contains, and commit or discard the pending bill.
//

import Foundation
import Combine

@MainActor
final class ShareScanModel: ObservableObject {
    @Published private(set) var billPages: [MedicalBillPage] = []
    @Published private(set) var anomalies: [BillCodeAnalyzer.Anomaly] = []
    @Published private(set) var isProcessing = false
    @Published private(set) var statusMessage: String?
    @Published private(set) var didSave = false
    @Published var errorMessage: String?

    private var sourceURL: String?
    private var hasStarted = false
    private let store = PendingBillStore()

    /// Runs once per share: restore the pending bill, then add this share's pages.
    func start(context: NSExtensionContext?) async {
        guard !hasStarted else { return }
        hasStarted = true
        isProcessing = true
        defer { isProcessing = false }

        let pending = store.load()
        billPages = pending.pages
        sourceURL = pending.sourceURL
        anomalies = BillCodeAnalyzer.crossPageAnomalies(in: billPages)

        append(await SharedInputLoader.load(from: context))
    }

    private func append(_ input: SharedInput) {
        sourceURL = sourceURL ?? input.sourceURL

        var added = 0, duplicates = 0
        for text in input.pageTexts {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if billPages.contains(where: { $0.rawText == trimmed }) {
                duplicates += 1
                continue
            }
            billPages.append(BillCodeAnalyzer.makePage(number: billPages.count + 1, rawText: trimmed))
            added += 1
        }
        anomalies = BillCodeAnalyzer.crossPageAnomalies(in: billPages)

        if added > 0 {
            statusMessage = "Added \(added) page\(added == 1 ? "" : "s") from this share."
        } else if duplicates > 0 {
            statusMessage = "This page was already captured, so it was not added again."
        } else if input.hadDocument {
            statusMessage = "No readable text was found in what you shared."
        } else {
            statusMessage = "This share only contained a link, which can't be scanned. Share a screenshot or a PDF of the page instead."
        }

        do {
            try store.save(PendingBill(sourceURL: sourceURL, pages: billPages))
        } catch {
            errorMessage = "The captured pages could not be kept for the next share: \(error.localizedDescription)"
        }
    }

    func commitSave() async {
        isProcessing = true
        defer { isProcessing = false }
        let payload = MedicalBillPayload(
            sourceURL: sourceURL,
            totalPages: billPages.count,
            pages: billPages,
            totalRiskAnomaliesFound: anomalies.count,
            clientScannedAt: Date())
        do {
            try await CloudKitManager.shared.saveMultiPageBill(payload: payload)
            store.clear()
            didSave = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func discard() {
        store.clear()
        billPages = []
        anomalies = []
        sourceURL = nil
        statusMessage = "Captured pages discarded."
    }
}
