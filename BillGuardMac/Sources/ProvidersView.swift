//
//  ProvidersView.swift
//  BillGuard (macOS)
//
//  Healthcare providers — Mac port of the iOS "Providers" tab (list only; the
//  iOS map / location-reminder features are device-oriented and omitted).
//

import SwiftUI
import BillGuardCore

struct ProvidersView: View {
    @StateObject private var data = PatientDataService.shared

    private var providers: [Provider] {
        data.providers.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        VStack(spacing: 0) {
            BrandHeader(title: "Providers", subtitle: providers.isEmpty ? nil : "\(providers.count) provider\(providers.count == 1 ? "" : "s")")
            if providers.isEmpty {
                ContentUnavailableView("No Providers", systemImage: "building.2",
                                       description: Text("Providers are added automatically from scanned bills."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(providers) { p in
                            HStack(spacing: 12) {
                                Image(systemName: p.providerType.icon).font(.title3)
                                    .foregroundStyle(.brandCyan).frame(width: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(p.name).font(.body.weight(.medium))
                                    Text([p.providerType.rawValue, p.specialty?.rawValue].compactMap { $0 }.joined(separator: " • "))
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
        .navigationTitle("Providers")
    }
}
