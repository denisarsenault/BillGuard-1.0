//
//  WebCaptureBridge.swift
//  BillGuardWebExtension
//
//  What the Safari Web Extension's popup can ask the app to do: show the pages
//  captured so far, add the page open in Safari, save the bill to iCloud, or
//  discard it. The same analyzer, pending-page store and CloudKit save as the
//  share extension (see docs/SHARE_EXTENSION_SPEC.md), fed with the page's own
//  text instead of OCR.
//

import Foundation

/// A message from popup.js.
struct WebCaptureRequest: Sendable {
    enum Action: String, Sendable {
        case state, capture, save, discard
    }

    var action: Action
    var text = ""
    var url: String?

    init(action: Action, text: String = "", url: String? = nil) {
        self.action = action
        self.text = text
        self.url = url
    }

    init?(message: Any?) {
        guard let fields = message as? [String: Any],
              let name = fields["action"] as? String,
              let action = Action(rawValue: name) else { return nil }
        self.init(action: action,
                  text: fields["text"] as? String ?? "",
                  url: fields["url"] as? String)
    }
}

/// The answer to popup.js: always the pending bill as it now stands, plus a
/// line to show.
struct WebCaptureReply: Sendable {
    var bill: PendingBill
    var message: String?
    var error: String?
    var saved = false

    var dictionary: [String: Any] {
        var fields: [String: Any] = [
            "pages": bill.pages.map { page in
                ["number": page.pageNumber,
                 "diagnoses": page.identifiedDiagnosticCodes.count,
                 "procedures": page.identifiedProcedureCodes.count,
                 "overlaps": page.overlappingCodes.count] as [String: Any]
            },
            "conflicts": BillCodeAnalyzer.crossPageAnomalies(in: bill.pages).map { anomaly in
                ["code": anomaly.code,
                 "kind": anomaly.kind == .duplicateProcedure ? "procedure" : "diagnosis",
                 "pages": anomaly.pageNumbers] as [String: Any]
            },
            "saved": saved,
        ]
        if let message { fields["message"] = message }
        if let error { fields["error"] = error }
        return fields
    }
}

enum WebCaptureBridge {

    /// Less text than this is a sign-in page or an empty frame, not a bill.
    static let minimumPageLength = 80
    /// A CloudKit record holds about 1 MB, and no bill page is this long.
    static let maximumPageLength = 60_000

    #if os(macOS)
    private static let savedPlace = "Web Captures"
    #else
    private static let savedPlace = "Shared Scans"
    #endif

    static func handle(_ request: WebCaptureRequest,
                       store: PendingBillStore = PendingBillStore()) async -> WebCaptureReply {
        var bill = store.load()

        switch request.action {
        case .state:
            return WebCaptureReply(bill: bill)

        case .capture:
            var reply = append(text: request.text, url: request.url, to: &bill)
            reply.bill = bill
            if reply.error == nil {
                do {
                    try store.save(bill)
                } catch {
                    reply.error = "The page could not be kept: \(error.localizedDescription)"
                }
            }
            return reply

        case .save:
            guard !bill.pages.isEmpty else {
                return WebCaptureReply(bill: bill, error: "Add a page before saving.")
            }
            let payload = MedicalBillPayload(
                sourceURL: bill.sourceURL,
                totalPages: bill.pages.count,
                pages: bill.pages,
                totalRiskAnomaliesFound: BillCodeAnalyzer.crossPageAnomalies(in: bill.pages).count,
                clientScannedAt: Date())
            do {
                try await CloudKitManager.shared.saveMultiPageBill(payload: payload)
                store.clear()
                return WebCaptureReply(
                    bill: PendingBill(),
                    message: "Saved. Open BillGuard and look under \(savedPlace).",
                    saved: true)
            } catch {
                return WebCaptureReply(bill: bill, error: error.localizedDescription)
            }

        case .discard:
            store.clear()
            return WebCaptureReply(bill: PendingBill(), message: "Captured pages discarded.")
        }
    }

    /// Adds the page to `bill` when it reads as a new bill page. The reply's
    /// `bill` is filled in by the caller.
    static func append(text: String, url: String?, to bill: inout PendingBill,
                       knownCodes: Set<String> = KnownProcedureCodes.bundled) -> WebCaptureReply {
        let (pageText, wasCut) = tidy(text)
        guard !pageText.isEmpty else {
            return WebCaptureReply(bill: bill, error:
                "No readable text was found on this page. For a PDF or a picture of a bill, use Share and choose BillGuard instead.")
        }
        guard pageText.count >= minimumPageLength else {
            return WebCaptureReply(bill: bill, error: "This page has too little text to be a bill.")
        }
        guard !bill.pages.contains(where: { $0.rawText == pageText }) else {
            return WebCaptureReply(bill: bill, message: "This page was already captured, so it was not added again.")
        }

        let page = BillCodeAnalyzer.makePage(number: bill.pages.count + 1, rawText: pageText,
                                             knownCodes: knownCodes)
        bill.pages.append(page)
        if bill.sourceURL == nil, let url, let parsed = URL(string: url),
           let scheme = parsed.scheme?.lowercased(), scheme == "http" || scheme == "https" {
            bill.sourceURL = url
        }

        var message = "Added page \(page.pageNumber)."
        if page.identifiedDiagnosticCodes.isEmpty && page.identifiedProcedureCodes.isEmpty {
            message += " No billing codes were found on it."
        }
        if wasCut {
            message += " The page was very long, so only the first part was kept."
        }
        return WebCaptureReply(bill: bill, message: message)
    }

    /// A web page's text, laid out like the text the analyzer and the apps'
    /// bill reader already handle: table cells apart by two spaces, no blank
    /// lines, ordinary spaces.
    static func tidy(_ text: String) -> (text: String, wasCut: Bool) {
        let lines = text
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\t", with: "  ")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let joined = lines.joined(separator: "\n")
        guard joined.count > maximumPageLength else { return (joined, false) }
        return (String(joined.prefix(maximumPageLength)), true)
    }
}
