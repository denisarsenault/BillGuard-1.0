//
//  WebCaptureHandoff.swift
//  BillGuard (macOS)
//
//  A bill sent by the BillGuard Chrome extension. Chrome cannot reach the app
//  the way the Safari extension does, so its Save opens a link:
//
//      billguard://web-capture?d=<base64url of {"v":1,"sourceURL":…,"pages":[text,…]}>
//
//  Anything on the Mac can open such a link, so nothing is saved from it
//  directly: the app finds the codes again itself, shows the bill, and saves
//  to iCloud only when the person chooses to.
//

import SwiftUI
import BillGuardCore
import os

struct WebCaptureHandoff: Identifiable {
    static let scheme = "billguard"
    static let host = "web-capture"
    /// Limits on what a link may carry; the extension stays well inside them.
    static let maximumPages = 50
    static let maximumEncodedLength = 600_000

    let id = UUID()
    let receivedAt = Date()
    let bill: PendingBill

    private struct Payload: Decodable {
        let v: Int
        let sourceURL: String?
        let pages: [String]
    }

    /// Nil when the link is not a bill this version can read.
    init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme, url.host == Self.host,
              let encoded = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                  .queryItems?.first(where: { $0.name == "d" })?.value,
              encoded.count <= Self.maximumEncodedLength,
              let data = Self.data(base64URL: encoded),
              let payload = try? JSONDecoder().decode(Payload.self, from: data),
              payload.v == 1, !payload.pages.isEmpty, payload.pages.count <= Self.maximumPages
        else { return nil }

        // The same steps as a page captured in Safari: tidied, checked for
        // length and repeats, and analyzed here rather than trusted.
        var bill = PendingBill()
        for text in payload.pages {
            _ = WebCaptureBridge.append(text: text, url: payload.sourceURL, to: &bill,
                                        knownCodes: Self.knownCodes)
        }
        guard !bill.pages.isEmpty else { return nil }
        self.bill = bill
    }

    /// The bill as it will appear under Web Captures once saved.
    var scan: SharedScan {
        SharedScan(id: id.uuidString, scannedAt: receivedAt, sourceURL: bill.sourceURL,
                   status: "PendingReview", pages: bill.pages)
    }

    var payload: MedicalBillPayload {
        MedicalBillPayload(sourceURL: bill.sourceURL,
                           totalPages: bill.pages.count,
                           pages: bill.pages,
                           totalRiskAnomaliesFound: BillCodeAnalyzer.crossPageAnomalies(in: bill.pages).count,
                           clientScannedAt: receivedAt)
    }

    /// The CPT and HCPCS codes in the app's database, as the extensions use
    /// them: a known code counts as billed even without a charge on its line.
    private static let knownCodes: Set<String> = {
        let shape = "^(?:\(BillCodeAnalyzer.cptPattern)|\(BillCodeAnalyzer.hcpcsPattern))$"
        return Set(MedicalCodeDatabase.allCodes.map(\.code).filter {
            $0.range(of: shape, options: .regularExpression) != nil
        })
    }()

    private static func data(base64URL: String) -> Data? {
        var base64 = base64URL.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        return Data(base64Encoded: base64)
    }
}

/// The review step for a bill that arrived from the browser.
struct WebCaptureReviewSheet: View {
    let handoff: WebCaptureHandoff
    /// Called with true once the bill is in iCloud, false if it was cancelled.
    let finish: (_ saved: Bool) -> Void

    @State private var isSaving = false
    @State private var problem: String?

    private static let log = Logger(subsystem: "com.mybrightzone.BillGuardMac", category: "WebCapture")

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Save Bill from Browser").font(.title2.bold())
                    Text("Sent by the BillGuard browser extension. Check it, then save it to Web Captures.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button("Cancel") { finish(false) }
                    .disabled(isSaving)
                Button(isSaving ? "Saving…" : "Save to iCloud") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(isSaving)
            }
            .padding()

            if let problem {
                Text(problem)
                    .font(.callout).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal).padding(.bottom, 10)
            }

            SharedScanDetailView(scan: handoff.scan,
                                 describe: { MedicalCodeDatabase.lookup($0)?.shortDescription })
        }
        .frame(minWidth: 560, idealWidth: 600, minHeight: 620, idealHeight: 700)
        .background(Color.brandScreen)
        .onAppear {
            Self.log.info("Web capture received: \(handoff.bill.pages.count) page(s)")
        }
    }

    private func save() {
        isSaving = true
        problem = nil
        Task {
            do {
                try await CloudKitManager.shared.saveMultiPageBill(payload: handoff.payload)
                Self.log.info("Web capture saved to iCloud")
                await SharedScanStore.shared.refresh()
                finish(true)
            } catch {
                Self.log.error("Web capture save failed: \(error.localizedDescription)")
                problem = error.localizedDescription
                isSaving = false
            }
        }
    }
}
