//
//  PatientDetailView.swift
//  BillGuard (macOS)
//
//  Shows a patient's saved bills (claims) using the shared ClaimSummary
//  projection from BillGuardCore — the destination after a scan is saved.
//

import SwiftUI
import BillGuardCore

struct PatientDetailView: View {
    let patient: Patient
    @StateObject private var data = PatientDataService.shared

    private var summaries: [ClaimSummary] {
        data.claims(for: patient.id)
            .map(\.summary)
            .sorted { $0.serviceDate > $1.serviceDate }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if summaries.isEmpty {
                    ContentUnavailableView("No Bills", systemImage: "doc.text.magnifyingglass",
                                           description: Text("Scanned or captured bills for \(patient.displayName) will appear here."))
                        .frame(maxWidth: .infinity, minHeight: 240)
                } else {
                    ForEach(summaries, id: \.claimId) { summary in
                        BillCard(summary: summary)
                    }
                }
            }
            .padding()
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(patient.displayName)
    }

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(.tint.opacity(0.15)).frame(width: 52, height: 52)
                Text(patient.initials).font(.title3.bold()).foregroundStyle(.tint)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(patient.displayName).font(.title2.bold())
                HStack(spacing: 6) {
                    if let age = patient.age { Text("Age \(age)") }
                    if patient.age != nil && !summaries.isEmpty { Text("·") }
                    if !summaries.isEmpty { Text("\(summaries.count) bill\(summaries.count == 1 ? "" : "s")") }
                }
                .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

/// One saved bill rendered from its ClaimSummary.
private struct BillCard: View {
    let summary: ClaimSummary

    // patientResponsibility is the bill's own Amount Due — already net of the
    // credits listed below, so it is shown as-is (not re-subtracted).
    private var amountDue: Double { summary.patientResponsibility }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(summary.providerName.isEmpty ? "Medical Bill" : summary.providerName)
                        .font(.headline)
                    HStack(spacing: 8) {
                        Text(summary.serviceDate.formatted(date: .abbreviated, time: .omitted))
                        if !summary.claimNumber.isEmpty { Text("· #\(summary.claimNumber)") }
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if !summary.statusLabel.isEmpty {
                    Text(summary.statusLabel.capitalized)
                        .font(.caption.bold())
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(.tint.opacity(0.15), in: Capsule())
                        .foregroundStyle(.tint)
                }
            }
            .padding(.bottom, 12)

            // Charges
            if !summary.charges.isEmpty {
                sectionLabel("Charges (\(summary.charges.count))")
                ForEach(summary.charges) { c in
                    HStack(spacing: 8) {
                        if !c.code.isEmpty {
                            Text(c.code).font(.system(.caption, design: .monospaced).bold())
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(.tint.opacity(0.15)).cornerRadius(4)
                        }
                        Text(c.description).lineLimit(1)
                        Spacer()
                        Text(c.amount, format: .currency(code: "USD")).monospacedDigit()
                    }
                    .font(.callout)
                    .padding(.vertical, 3)
                }
                Divider().padding(.vertical, 6)
            }

            // Payments & credits
            let allPayments = summary.insurancePayments + summary.patientPayments
            if !allPayments.isEmpty {
                sectionLabel("Payments & Credits")
                ForEach(summary.insurancePayments) { p in paymentRow(p.label, p.amount, insurance: true) }
                ForEach(summary.patientPayments) { p in paymentRow(p.label, p.amount, insurance: false) }
                Divider().padding(.vertical, 6)
            }

            // Totals
            totalRow("Billed", summary.billedAmount, bold: false)
            if summary.insurancePaidTotal != 0 { totalRow("Insurance Paid", -summary.insurancePaidTotal, bold: false, green: true) }
            if summary.patientPaidTotal != 0 { totalRow("Patient Paid", -summary.patientPaidTotal, bold: false, green: true) }
            totalRow("Amount Due", amountDue, bold: true, emphasize: true)
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator))
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.caption2.bold()).foregroundStyle(.secondary)
            .padding(.bottom, 4)
    }

    private func paymentRow(_ label: String, _ amount: Double, insurance: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: insurance ? "shield.lefthalf.filled" : "creditcard")
                .foregroundStyle(.green)
            Text(label.isEmpty ? (insurance ? "Insurance Payment" : "Patient Payment") : label).lineLimit(1)
            Spacer()
            Text(-abs(amount), format: .currency(code: "USD"))
                .monospacedDigit().foregroundStyle(.green)
        }
        .font(.callout).padding(.vertical, 3)
    }

    private func totalRow(_ label: String, _ amount: Double, bold: Bool, emphasize: Bool = false, green: Bool = false) -> some View {
        HStack {
            Text(label).fontWeight(bold ? .bold : .regular)
            Spacer()
            Text(amount, format: .currency(code: "USD"))
                .monospacedDigit()
                .fontWeight(bold ? .bold : .regular)
                .foregroundStyle(emphasize ? Color.red : (green ? Color.green : Color.primary))
        }
        .padding(.vertical, 2)
    }
}
