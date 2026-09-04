//
//  VisitsView.swift
//  BillGuard (macOS)
//
//  Patient visits / appointments — Mac port of the iOS "Visits" tab.
//

import SwiftUI
import BillGuardCore

struct VisitsView: View {
    @StateObject private var data = PatientDataService.shared

    private func patientName(_ id: String) -> String {
        data.patients.first { $0.id == id }?.displayName ?? "Unknown Patient"
    }
    private var visits: [Visit] { data.visits.sorted { $0.visitDate > $1.visitDate } }

    var body: some View {
        VStack(spacing: 0) {
            BrandHeader(title: "Visits", subtitle: visits.isEmpty ? nil : "\(visits.count) visit\(visits.count == 1 ? "" : "s")")
            if visits.isEmpty {
                ContentUnavailableView("No Visits", systemImage: "calendar.badge.clock",
                                       description: Text("Visits recorded for your patients appear here."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(visits) { v in
                            HStack(spacing: 12) {
                                Image(systemName: v.visitType.icon).font(.title3)
                                    .foregroundStyle(.brandCyan).frame(width: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(v.providerName ?? v.visitType.rawValue).font(.body.weight(.medium))
                                    Text("\(patientName(v.patientId))  •  \(v.visitDate.formatted(date: .abbreviated, time: .omitted))")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(v.status.rawValue).font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(.brandCyan.opacity(0.15), in: Capsule())
                                    .foregroundStyle(.brandCyan)
                            }
                            .navyCard(padding: 12)
                        }
                    }
                    .padding(16)
                }
            }
        }
        .brandScreen()
        .navigationTitle("Visits")
    }
}
