//
//  InsuranceView.swift
//  BillGuard (macOS)
//
//  Insurance policies — Mac port of the iOS "Insurance" tab.
//

import SwiftUI
import BillGuardCore

struct InsuranceView: View {
    @StateObject private var data = PatientDataService.shared

    private func patientName(_ id: String) -> String {
        data.patients.first { $0.id == id }?.displayName ?? "Unknown Patient"
    }
    private func carrierName(_ id: String) -> String {
        data.insuranceCarriers.first { $0.id == id }?.name ?? "Insurance"
    }
    private var policies: [InsurancePolicy] {
        data.insurancePolicies.sorted { ($0.isPrimary ? 0 : 1) < ($1.isPrimary ? 0 : 1) }
    }

    var body: some View {
        VStack(spacing: 0) {
            BrandHeader(title: "Insurance", subtitle: policies.isEmpty ? nil : "\(policies.count) polic\(policies.count == 1 ? "y" : "ies")")
            if policies.isEmpty {
                ContentUnavailableView("No Policies", systemImage: "shield.lefthalf.filled",
                                       description: Text("Insurance policies for your patients appear here."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(policies) { pol in
                            HStack(spacing: 12) {
                                Image(systemName: "shield.lefthalf.filled").font(.title3)
                                    .foregroundStyle(.brandCyan).frame(width: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(pol.planName ?? carrierName(pol.carrierId)).font(.body.weight(.medium))
                                        if pol.isPrimary {
                                            Text("PRIMARY").font(.system(size: 9, weight: .bold))
                                                .padding(.horizontal, 5).padding(.vertical, 1)
                                                .background(.green.opacity(0.2), in: Capsule()).foregroundStyle(.green)
                                        }
                                    }
                                    Text("\(patientName(pol.patientId))  •  \(carrierName(pol.carrierId))  •  Member \(pol.memberId)")
                                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer()
                                Text(pol.policyType.rawValue).font(.caption2).foregroundStyle(.secondary)
                            }
                            .navyCard(padding: 12)
                        }
                    }
                    .padding(16)
                }
            }
        }
        .brandScreen()
        .navigationTitle("Insurance")
    }
}
