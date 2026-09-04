//
//  PaymentsView.swift
//  BillGuard (macOS)
//
//  Patient payment methods — Mac port of the iOS "Payments" tab.
//

import SwiftUI
import BillGuardCore

struct PaymentsView: View {
    @StateObject private var data = PatientDataService.shared

    private func patientName(_ id: String) -> String {
        data.patients.first { $0.id == id }?.displayName ?? "Unknown Patient"
    }
    private var methods: [PaymentMethod] {
        data.paymentMethods.sorted { ($0.isDefault ? 0 : 1) < ($1.isDefault ? 0 : 1) }
    }

    private func subtitle(_ m: PaymentMethod) -> String {
        if let last = m.lastFourDigits ?? m.accountLastFour {
            return "•••• \(last)"
        }
        return m.type.rawValue
    }

    var body: some View {
        VStack(spacing: 0) {
            BrandHeader(title: "Payments", subtitle: methods.isEmpty ? nil : "\(methods.count) method\(methods.count == 1 ? "" : "s")")
            if methods.isEmpty {
                ContentUnavailableView("No Payment Methods", systemImage: "creditcard",
                                       description: Text("Saved cards and accounts for your patients appear here."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(methods) { m in
                            HStack(spacing: 12) {
                                Image(systemName: m.type.icon).font(.title3)
                                    .foregroundStyle(.brandCyan).frame(width: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(m.nickname ?? m.cardBrand?.rawValue ?? m.type.rawValue)
                                            .font(.body.weight(.medium))
                                        if m.isDefault {
                                            Text("DEFAULT").font(.system(size: 9, weight: .bold))
                                                .padding(.horizontal, 5).padding(.vertical, 1)
                                                .background(.brandCyan.opacity(0.2), in: Capsule()).foregroundStyle(.brandCyan)
                                        }
                                    }
                                    Text("\(patientName(m.patientId))  •  \(subtitle(m))")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .navyCard(padding: 12)
                        }
                    }
                    .padding(16)
                }
            }
        }
        .brandScreen()
        .navigationTitle("Payments")
    }
}
