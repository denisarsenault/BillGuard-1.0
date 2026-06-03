//
//  CodeDetailView.swift
//  BillGuard
//
//  Detailed view for a medical code
//

import SwiftUI

struct CodeDetailView: View {
    
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    
    let code: MedicalCode
    
    @State private var relatedCodes: [MedicalCode] = []
    @State private var isLoadingRelated = false
    @State private var showShareSheet = false
    
    private var isFavorite: Bool {
        appState.favoritesManager.isFavorite(code)
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                
                // Header Card
                headerCard
                
                // Description Section
                descriptionSection
                
                // Pricing Section
                if code.hasValidPricing {
                    pricingSection
                }
                
                // Common Uses Section
                if !code.commonUses.isEmpty {
                    commonUsesSection
                }
                
                // Insurance Notes
                if let notes = code.insuranceNotes {
                    insuranceNotesSection(notes)
                }
                
                // Misuse Warning
                if let warning = code.misuseWarning {
                    misuseWarningSection(warning)
                }
                
                // Related Codes
                if !code.relatedCodes.isEmpty {
                    relatedCodesSection
                }
                
                Spacer(minLength: 40)
            }
            .padding()
        }
        .navigationTitle("Code Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                // Share Button
                Button {
                    showShareSheet = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                
                // Favorite Button
                Button {
                    appState.favoritesManager.toggleFavorite(code)
                } label: {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .foregroundColor(isFavorite ? .yellow : .primary)
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(items: [shareText])
        }
        .task {
            await loadRelatedCodes()
        }
    }
    
    // MARK: - Header Card
    
    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Code Type Badge
            HStack {
                Text(code.codeType.displayName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(codeTypeColor)
                    .cornerRadius(8)
                
                Spacer()
                
                Text(code.category)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Code Number
            Text(code.code)
                .font(.system(size: 42, weight: .bold, design: .rounded))
            
            // Short Description
            Text(code.shortDescription)
                .font(.title3)
                .foregroundColor(.secondary)
        }
        .padding(20)
        .background(Color(.systemGray6))
        .cornerRadius(16)
    }
    
    // MARK: - Description Section
    
    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Plain English Explanation", icon: "text.quote")
            
            Text(code.plainEnglishDescription)
                .font(.body)
                .lineSpacing(6)
                .foregroundColor(.primary)
        }
    }
    
    // MARK: - Pricing Section
    
    private var pricingSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "Typical Pricing", icon: "dollarsign.circle")
            
            HStack(spacing: 0) {
                // Low Price
                PriceColumn(
                    label: "Low",
                    value: code.priceLow.map { "$\(Int($0))" } ?? "N/A",
                    color: .green
                )
                
                Divider()
                    .frame(height: 60)
                
                // Average Price
                PriceColumn(
                    label: "Average",
                    value: code.priceAverage.map { "$\(Int($0))" } ?? "N/A",
                    color: .blue,
                    isHighlighted: true
                )
                
                Divider()
                    .frame(height: 60)
                
                // High Price
                PriceColumn(
                    label: "High",
                    value: code.priceHigh.map { "$\(Int($0))" } ?? "N/A",
                    color: .orange
                )
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
            
            Text("Prices shown are national averages and may vary by location and provider.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Common Uses Section
    
    private var commonUsesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Common Uses", icon: "list.bullet")
            
            VStack(alignment: .leading, spacing: 10) {
                ForEach(code.commonUses, id: \.self) { use in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.body)
                        
                        Text(use)
                            .font(.body)
                    }
                }
            }
        }
    }
    
    // MARK: - Insurance Notes Section
    
    private func insuranceNotesSection(_ notes: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Insurance Notes", icon: "shield.checkered")
            
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(.blue)
                    .font(.title3)
                
                Text(notes)
                    .font(.body)
                    .lineSpacing(4)
            }
            .padding()
            .background(Color("BrandCyan").opacity(0.1))
            .cornerRadius(12)
        }
    }
    
    // MARK: - Misuse Warning Section
    
    private func misuseWarningSection(_ warning: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Watch Out For", icon: "exclamationmark.triangle")
            
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.title3)
                
                Text(warning)
                    .font(.body)
                    .lineSpacing(4)
            }
            .padding()
            .background(Color.orange.opacity(0.1))
            .cornerRadius(12)
        }
    }
    
    // MARK: - Related Codes Section
    
    private var relatedCodesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Related Codes", icon: "link")
            
            if isLoadingRelated {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .padding()
            } else if relatedCodes.isEmpty {
                // Show code numbers as chips if we couldn't load details
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(code.relatedCodes, id: \.self) { relatedCode in
                            Text(relatedCode)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Color(.systemGray5))
                                .cornerRadius(8)
                        }
                    }
                }
            } else {
                VStack(spacing: 10) {
                    ForEach(relatedCodes) { relatedCode in
                        NavigationLink(destination: CodeDetailView(code: relatedCode).environmentObject(appState)) {
                            RelatedCodeRow(code: relatedCode)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
    
    // MARK: - Helper Properties
    
    private var codeTypeColor: Color {
        switch code.codeType {
        case .cpt: return .blue
        case .icd10: return .green
        case .icd10pcs: return .teal
        case .hcpcs: return .orange
        }
    }
    
    private var shareText: String {
        var text = "Medical Code: \(code.code)\n"
        text += "\(code.codeType.displayName)\n\n"
        text += "\(code.shortDescription)\n\n"
        text += code.plainEnglishDescription
        
        if code.hasValidPricing {
            text += "\n\nTypical Price: \(code.formattedPriceRange)"
        }
        
        text += "\n\nShared via BillGuard"
        return text
    }
    
    // MARK: - Load Related Codes
    
    private func loadRelatedCodes() async {
        guard !code.relatedCodes.isEmpty else { return }
        
        isLoadingRelated = true
        
        do {
            relatedCodes = try await appState.cloudKitService.fetchRelatedCodes(for: code)
        } catch {
            // Silent fail - we'll show the code numbers instead
            print("Failed to load related codes: \(error)")
        }
        
        isLoadingRelated = false
    }
}

// MARK: - Section Header

struct SectionHeader: View {
    let title: String
    let icon: String
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(.accentColor)
            Text(title)
                .font(.headline)
        }
    }
}

// MARK: - Price Column

struct PriceColumn: View {
    let label: String
    let value: String
    let color: Color
    var isHighlighted: Bool = false
    
    var body: some View {
        VStack(spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text(value)
                .font(isHighlighted ? .title2 : .title3)
                .fontWeight(.bold)
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Related Code Row

struct RelatedCodeRow: View {
    let code: MedicalCode
    
    var body: some View {
        HStack(spacing: 12) {
            Text(code.code)
                .font(.headline)
                .fontWeight(.semibold)
            
            Text(code.shortDescription)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(1)
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    NavigationStack {
        CodeDetailView(code: .sample)
            .environmentObject(AppState())
    }
}
