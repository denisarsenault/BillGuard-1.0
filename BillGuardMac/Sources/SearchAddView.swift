//
//  SearchAddView.swift
//  BillGuard (macOS)
//
//  Medical-code search (CPT / ICD-10 / HCPCS) over the bundled database, with a
//  type filter and favoriting — the Mac counterpart to the iOS "Search & Add" tab.
//

import SwiftUI
import BillGuardCore

func codeTypeLabel(_ t: MedicalCodeType) -> String { t.rawValue }

struct SearchAddView: View {
    @StateObject private var favorites = FavoritesManager.shared
    @State private var query = ""
    @State private var typeFilter: MedicalCodeType?
    @State private var selected: MedicalCode?

    private var results: [MedicalCode] {
        MedicalCodeDatabase.search(query, type: typeFilter, limit: 200)
    }

    var body: some View {
        VStack(spacing: 0) {
            BrandHeader(title: "Search & Add", subtitle: "\(MedicalCodeDatabase.count) codes • CPT, ICD-10, HCPCS")

            // Search field + filters
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search a code or description (e.g. 99213, chest x-ray)", text: $query)
                        .textFieldStyle(.plain)
                    if !query.isEmpty {
                        Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain).foregroundStyle(.secondary)
                    }
                }
                .padding(10)
                .background(Color.brandCyan.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.brandCyan.opacity(0.18)))

                HStack(spacing: 8) {
                    FilterChip(title: "All", isOn: typeFilter == nil, color: .brandCyan) { typeFilter = nil }
                    ForEach(MedicalCodeType.allCases, id: \.self) { t in
                        FilterChip(title: codeTypeLabel(t), isOn: typeFilter == t, color: .codeType(t)) {
                            typeFilter = (typeFilter == t) ? nil : t
                        }
                    }
                    Spacer()
                    Text("\(results.count) result\(results.count == 1 ? "" : "s")")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(16)

            // Results
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(results) { code in
                        CodeRow(code: code,
                                isFavorite: favorites.isFavorite(code),
                                onToggleFavorite: { favorites.toggleFavorite(code) })
                            .contentShape(Rectangle())
                            .onTapGesture { selected = code }
                    }
                    if results.isEmpty {
                        ContentUnavailableView("No matches", systemImage: "magnifyingglass",
                                               description: Text("Try a different code or keyword."))
                            .padding(.top, 60)
                    }
                }
                .padding(16)
            }
        }
        .brandScreen()
        .navigationTitle("Search & Add")
        .sheet(item: $selected) { code in
            CodeDetailView(code: code)
        }
    }
}

struct FilterChip: View {
    let title: String
    let isOn: Bool
    var color: Color = .brandCyan
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(isOn ? color : color.opacity(0.12), in: Capsule())
                .foregroundStyle(isOn ? Color.black : color)
        }
        .buttonStyle(.plain)
    }
}

struct CodeRow: View {
    let code: MedicalCode
    var isFavorite: Bool
    var onToggleFavorite: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    CodeTypeBadge(text: code.code, color: .codeType(code.codeType))
                    Text(codeTypeLabel(code.codeType))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.codeType(code.codeType))
                }
                Text(code.shortDescription).font(.body).foregroundStyle(.primary).lineLimit(2)
                if code.hasValidPricing {
                    Text("Typical: \(code.formattedPriceRange)")
                        .font(.caption).foregroundStyle(.green)
                }
            }
            Spacer()
            Button(action: onToggleFavorite) {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .foregroundStyle(isFavorite ? .yellow : .secondary)
            }
            .buttonStyle(.plain)
        }
        .navyCard(padding: 12)
    }
}
