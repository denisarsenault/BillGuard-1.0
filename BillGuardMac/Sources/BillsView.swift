//
//  BillsView.swift
//  BillGuard (macOS)
//
//  All bills (claims) across every patient — Mac port of the iOS "Bills" tab.
//

import SwiftUI
import BillGuardCore

struct BillsView: View {
    @StateObject private var data = PatientDataService.shared
    @State private var openBill: ClaimSummary?

    /// (patient, summary) pairs, newest first.
    private var bills: [(patient: Patient, summary: ClaimSummary)] {
        data.patients.flatMap { p in
            data.claims(for: p.id).map { (p, $0.summary) }
        }
        .sorted { $0.1.serviceDate > $1.1.serviceDate }
    }

    var body: some View {
        VStack(spacing: 0) {
            BrandHeader(title: "Bills", subtitle: bills.isEmpty ? nil : "\(bills.count) bill\(bills.count == 1 ? "" : "s")")

            if bills.isEmpty {
                ContentUnavailableView("No Bills Yet", systemImage: "doc.text",
                                       description: Text("Scan a document or capture a web portal to add a bill."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(bills, id: \.summary.claimId) { item in
                            BillRow(patientName: item.patient.displayName, summary: item.summary)
                                .contentShape(Rectangle())
                                .onTapGesture { openBill = item.summary }
                        }
                    }
                    .padding(16)
                }
            }
        }
        .brandScreen()
        .navigationTitle("Bills")
        .sheet(item: Binding(get: { openBill.map(SummaryBox.init) },
                             set: { openBill = $0?.summary })) { box in
            BillSheet(summary: box.summary)
        }
    }
}

private struct SummaryBox: Identifiable { let summary: ClaimSummary; var id: String { summary.claimId } }

private struct BillRow: View {
    let patientName: String
    let summary: ClaimSummary
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text.fill").font(.title3).foregroundStyle(.brandCyan)
            VStack(alignment: .leading, spacing: 2) {
                Text(summary.providerName.isEmpty ? "Medical Bill" : summary.providerName)
                    .font(.body.weight(.medium)).lineLimit(1)
                Text("\(patientName)  •  \(summary.serviceDate.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(summary.patientResponsibility, format: .currency(code: "USD"))
                    .font(.body.weight(.semibold).monospacedDigit())
                if !summary.statusLabel.isEmpty {
                    Text(summary.statusLabel.capitalized).font(.caption2).foregroundStyle(.brandCyan)
                }
            }
        }
        .navyCard(padding: 12)
    }
}

private struct BillSheet: View {
    let summary: ClaimSummary
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Bill Detail").font(.title2.bold())
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }.padding()
            ScrollView { BillCard(summary: summary).padding(16) }
        }
        .frame(minWidth: 520, minHeight: 560)
        .background(Color.brandScreen)
    }
}
