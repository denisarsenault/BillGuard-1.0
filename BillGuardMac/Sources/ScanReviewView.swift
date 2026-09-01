//
//  ScanReviewView.swift
//  BillGuard (macOS)
//
//  Read-only review of a parsed bill (BillParseResult) from the shared parser.
//  Saving to the data layer is wired in a follow-up step.
//

import SwiftUI
import BillGuardCore

struct ScanReviewView: View {
    let result: BillParseResult
    var onClose: () -> Void

    private var charges: [ParsedLineItem] { result.lineItems.filter { $0.kind == .charge } }
    private var credits: [ParsedLineItem] { result.lineItems.filter { $0.kind == .payment } }
    private var chargesTotal: Double { charges.reduce(0) { $0 + $1.amount } }
    private var creditsTotal: Double { credits.reduce(0) { $0 + $1.amount } }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Review Bill").font(.title2.bold())
                Spacer()
                Button("Done") { onClose() }.keyboardShortcut(.defaultAction)
            }
            .padding()

            Form {
                if !result.providerName.isEmpty || !result.providerAddress.isEmpty {
                    Section("Provider") {
                        row("Facility", result.providerName)
                        row("Address", result.providerAddress)
                        row("Phone", result.providerPhone)
                        row("Fax", result.providerFax)
                    }
                }
                Section("Patient") {
                    row("Name", result.patientName)
                    row("Account #", result.accountNumber)
                    row("MRN", result.mrn)
                    row("Date of Birth", result.dateOfBirth)
                    row("Service Date", result.serviceDate.formatted(date: .abbreviated, time: .omitted))
                }
                if !result.insuranceCarrier.isEmpty || !result.policyNumber.isEmpty {
                    Section("Insurance") {
                        row("Carrier", result.insuranceCarrier)
                        row("Policy #", result.policyNumber)
                        row("Member ID", result.memberId)
                        row("Plan Type", result.insurancePlanType)
                    }
                }

                Section("Charges (\(charges.count))") {
                    ForEach(charges) { item in
                        HStack {
                            if !item.code.isEmpty {
                                Text(item.code).font(.system(.caption, design: .monospaced).bold())
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(.tint.opacity(0.15)).cornerRadius(4)
                            }
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.bestDescription)
                                if let range = item.databasePriceRange {
                                    Text("Typical: \(range)").font(.caption).foregroundStyle(.green)
                                }
                            }
                            Spacer()
                            Text(item.amount, format: .currency(code: "USD")).monospacedDigit()
                        }
                    }
                    HStack { Text("Charges Total").bold(); Spacer()
                        Text(chargesTotal, format: .currency(code: "USD")).bold().foregroundStyle(.tint) }
                }

                if !credits.isEmpty {
                    Section("Payments & Credits (\(credits.count))") {
                        ForEach(credits) { item in
                            HStack {
                                Image(systemName: "arrow.down.left.circle.fill").foregroundStyle(.green)
                                Text(item.description.isEmpty ? "Payment / Credit" : item.description)
                                Spacer()
                                Text(item.amount, format: .currency(code: "USD"))
                                    .monospacedDigit().foregroundStyle(item.amount < 0 ? .green : .secondary)
                            }
                        }
                        HStack { Text("Payments & Credits").bold(); Spacer()
                            Text(creditsTotal, format: .currency(code: "USD")).bold().foregroundStyle(.green) }
                    }
                }

                Section("Financial Summary") {
                    row("Billed", result.billedAmount)
                    row("Insurance Adjustment", result.insuranceAdjustment)
                    row("Insurance Paid", result.insurancePaid)
                    row("Amount Due", result.amountDue, emphasize: true)
                }
            }
            .formStyle(.grouped)
        }
        .frame(minWidth: 560, minHeight: 640)
    }

    @ViewBuilder private func row(_ label: String, _ value: String, emphasize: Bool = false) -> some View {
        if !value.isEmpty {
            LabeledContent(label) {
                Text(value).foregroundStyle(emphasize ? Color.red : .primary)
                    .fontWeight(emphasize ? .bold : .regular)
            }
        }
    }
}
