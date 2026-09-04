//
//  SavedView.swift
//  BillGuard (macOS)
//
//  Saved medical codes (favorites), with a type filter — Mac port of the iOS
//  "Saved" tab.
//

import SwiftUI
import BillGuardCore

struct SavedView: View {
    @StateObject private var favorites = FavoritesManager.shared
    @State private var typeFilter: MedicalCodeType?
    @State private var selected: MedicalCode?

    private var items: [MedicalCode] {
        let all = favorites.favorites
        guard let typeFilter else { return all }
        return all.filter { $0.codeType == typeFilter }
    }

    var body: some View {
        VStack(spacing: 0) {
            BrandHeader(title: "Saved", subtitle: favorites.count == 0 ? nil : "\(favorites.count) saved code\(favorites.count == 1 ? "" : "s")")

            if favorites.count == 0 {
                ContentUnavailableView("No Saved Codes", systemImage: "star",
                                       description: Text("Tap the star on any code in Search & Add to save it here."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 8) {
                    FilterChip(title: "All", isOn: typeFilter == nil, color: .brandCyan) { typeFilter = nil }
                    ForEach(MedicalCodeType.allCases, id: \.self) { t in
                        FilterChip(title: codeTypeLabel(t), isOn: typeFilter == t, color: .codeType(t)) {
                            typeFilter = (typeFilter == t) ? nil : t
                        }
                    }
                    Spacer()
                    Button(role: .destructive) { favorites.clearAll() } label: {
                        Label("Clear All", systemImage: "trash")
                    }.buttonStyle(.plain).foregroundStyle(.red).font(.caption)
                }
                .padding(16)

                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(items) { code in
                            CodeRow(code: code, isFavorite: true,
                                    onToggleFavorite: { favorites.toggleFavorite(code) })
                                .contentShape(Rectangle())
                                .onTapGesture { selected = code }
                        }
                    }
                    .padding(16)
                }
            }
        }
        .brandScreen()
        .navigationTitle("Saved")
        .sheet(item: $selected) { CodeDetailView(code: $0) }
    }
}
