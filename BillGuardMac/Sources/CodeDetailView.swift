//
//  CodeDetailView.swift
//  BillGuard (macOS)
//
//  Full detail for a MedicalCode — plain-English explanation, pricing, common
//  uses, insurance notes, misuse warning, related codes. Mac port of the iOS
//  CodeDetailView (UIKit share swapped for NSSharingServicePicker).
//

import SwiftUI
import BillGuardCore

struct CodeDetailView: View {
    let code: MedicalCode
    @Environment(\.dismiss) private var dismiss
    @StateObject private var favorites = FavoritesManager.shared

    private var isFavorite: Bool { favorites.isFavorite(code) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(codeTypeLabel(code.codeType)).font(.headline).foregroundStyle(.codeType(code.codeType))
                Spacer()
                Button { favorites.toggleFavorite(code) } label: {
                    Label(isFavorite ? "Saved" : "Save",
                          systemImage: isFavorite ? "star.fill" : "star")
                        .foregroundStyle(isFavorite ? .yellow : .brandCyan)
                }.buttonStyle(.bordered)
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Header card
                    VStack(alignment: .leading, spacing: 8) {
                        CodeTypeBadge(text: code.code, color: .codeType(code.codeType))
                        Text(code.shortDescription).font(.title2.bold())
                        Text(code.category + (code.subcategory.map { " • \($0)" } ?? ""))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .navyCard()

                    if !code.plainEnglishDescription.isEmpty {
                        section("What it means", icon: "text.book.closed") {
                            Text(code.plainEnglishDescription).foregroundStyle(.primary)
                        }
                    }

                    if code.hasValidPricing {
                        section("Typical Pricing", icon: "dollarsign.circle") {
                            HStack(spacing: 12) {
                                priceCol("Low", code.priceLow, .green)
                                priceCol("Average", code.priceAverage, .brandCyan)
                                priceCol("High", code.priceHigh, .orange)
                            }
                        }
                    }

                    if !code.commonUses.isEmpty {
                        section("Common Uses", icon: "list.bullet") {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(code.commonUses, id: \.self) { use in
                                    Label(use, systemImage: "checkmark.circle.fill")
                                        .foregroundStyle(.primary)
                                        .labelStyle(.titleAndIcon)
                                }
                            }
                        }
                    }

                    if let notes = code.insuranceNotes, !notes.isEmpty {
                        section("Insurance Notes", icon: "shield.lefthalf.filled", tint: .brandCyan) {
                            Text(notes)
                        }
                    }

                    if let warn = code.misuseWarning, !warn.isEmpty {
                        section("Watch Out", icon: "exclamationmark.triangle.fill", tint: .orange) {
                            Text(warn)
                        }
                    }

                    if !code.relatedCodes.isEmpty {
                        section("Related Codes", icon: "link") {
                            FlowChips(items: code.relatedCodes)
                        }
                    }
                }
                .padding(16)
            }
        }
        .frame(minWidth: 560, minHeight: 620)
        .background(Color.brandScreen)
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, icon: String, tint: Color = .secondary,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon).font(.headline).foregroundStyle(tint == .secondary ? .brandCyan : tint)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .navyCard()
    }

    private func priceCol(_ label: String, _ value: Double?, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value.map { $0.formatted(.currency(code: "USD")) } ?? "—")
                .font(.title3.bold().monospacedDigit()).foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
    }
}

/// Simple wrapping chip row.
struct FlowChips: View {
    let items: [String]
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 6)], alignment: .leading, spacing: 6) {
            ForEach(items, id: \.self) { CodeTypeBadge(text: $0, color: .brandCyan) }
        }
    }
}

#Preview {
    CodeDetailView(code: MedicalCode.sample)
}
