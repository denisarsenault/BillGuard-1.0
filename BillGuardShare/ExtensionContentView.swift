//
//  ExtensionContentView.swift
//  BillGuardShare
//
//  Share-sheet UI from docs/SHARE_EXTENSION_SPEC.md (section 6), adapted to the
//  share-once-per-page flow: each share appends its page, the sheet shows the
//  running breakdown and the cross-page warning banner. Styled to match the
//  main app (dark, navy surfaces, cyan tint) using the app's asset catalog.
//  Shared by the iOS and macOS share extensions.
//

import SwiftUI

/// The main app's palette, read from the shared Assets.xcassets.
private enum Brand {
    static let cyan = Color("BrandCyan")
    static let teal = Color("BrandTeal")
    static let navy = Color("BrandNavy")          // cards, bars
    static let deepNavy = Color("BrandDeepNavy")  // screen background
    static let diagnosis = Color.green            // ICD-10, as in the app
    static let procedure = Color("BrandCyan")     // CPT, as in the app
}

struct ExtensionContentView: View {
    var extensionContext: NSExtensionContext?

    @StateObject private var model = ShareScanModel()

    private static let keepHint = "Pages are kept when you choose Done. Share the next page to add it, then Commit Save when the bill is complete."

    var body: some View {
        chrome
            .tint(Brand.cyan)
            .preferredColorScheme(.dark)   // BillGuard is dark-only, like the app
            .task { await model.start(context: extensionContext) }
            .onChange(of: model.didSave) { _, saved in
                if saved { finish() }
            }
            .alert("BillGuard", isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } })) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(model.errorMessage ?? "")
            }
    }

    /// The shared content inside each platform's bar: a navigation bar on iOS,
    /// a plain header row on macOS (a share sheet there has no toolbar).
    @ViewBuilder private var chrome: some View {
        #if os(macOS)
        VStack(spacing: 0) {
            HStack {
                Button("Done") { finish() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                brandTitle
                Spacer()
                Button("Commit Save") { Task { await model.commitSave() } }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.billPages.isEmpty || model.isProcessing)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Brand.navy)
            content
        }
        .frame(width: 460, height: 600)
        #else
        NavigationStack {
            content
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(Brand.navy, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Done") { finish() }
                    }
                    ToolbarItem(placement: .principal) {
                        brandTitle
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Commit Save") { Task { await model.commitSave() } }
                            .fontWeight(.semibold)
                            .disabled(model.billPages.isEmpty || model.isProcessing)
                    }
                }
        }
        #endif
    }

    private var content: some View {
            VStack(spacing: 0) {
                if !model.anomalies.isEmpty {
                    warningBanner
                }

                List {
                    if let status = model.statusMessage {
                        Section {
                            Label {
                                Text(status).font(.subheadline)
                            } icon: {
                                Image(systemName: "info.circle").foregroundStyle(Brand.cyan)
                            }
                        }
                        .listRowBackground(Brand.navy)
                    }

                    Section {
                        if model.isProcessing && model.billPages.isEmpty {
                            HStack(spacing: 10) {
                                ProgressView().tint(Brand.cyan)
                                Text("Reading what you shared…").foregroundStyle(.secondary)
                            }
                        } else if model.billPages.isEmpty {
                            emptyState
                        } else {
                            ForEach(model.billPages) { page in
                                pageRow(page)
                            }
                            #if os(macOS)
                            // A Mac list footer is clipped to one line, so the hint is a row.
                            Text(Self.keepHint)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            #endif
                        }
                    } header: {
                        sectionHeader("Captured Breakdown")
                    } footer: {
                        #if !os(macOS)
                        if !model.billPages.isEmpty {
                            Text(Self.keepHint)
                        }
                        #endif
                    }
                    .listRowBackground(Brand.navy)

                    if !model.anomalies.isEmpty {
                        Section {
                            ForEach(model.anomalies) { anomaly in
                                anomalyRow(anomaly)
                            }
                        } header: {
                            sectionHeader("Cross-Page Conflicts")
                        }
                        .listRowBackground(Brand.navy)
                    }

                    if !model.billPages.isEmpty {
                        Section {
                            Button("Discard Captured Pages", role: .destructive) {
                                model.discard()
                            }
                            .disabled(model.isProcessing)
                        }
                        .listRowBackground(Brand.navy)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .background(Brand.deepNavy.ignoresSafeArea())
            .animation(.default, value: model.anomalies)
    }

    /// Shield logo + gradient wordmark, as in the app's BrandToolbar.
    private var brandTitle: some View {
        HStack(spacing: 7) {
            Image("BrandLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 26, height: 26)
            // Just the wordmark: the bar also holds Done and Commit Save.
            Text("BillGuard")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(
                    LinearGradient(colors: [Brand.cyan, Brand.teal],
                                   startPoint: .leading, endPoint: .trailing))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("BillGuard Scanner")
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Brand.cyan.opacity(0.8))
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image("BrandLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 56, height: 56)
                .shadow(color: Brand.cyan.opacity(0.45), radius: 12)
            Text("No pages captured yet")
                .font(.headline)
            Text("Share a screenshot or PDF of each bill page from your browser.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
    }

    private var warningBanner: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.yellow)
                Text("High-Risk Code Overlap Detected")
                    .font(.headline)
                    .foregroundColor(.white)
            }
            Text("We detected \(model.anomalies.count) diagnostic or procedure code conflict\(model.anomalies.count == 1 ? "" : "s") across your captured pages. Review these anomalies before final save.")
                .font(.caption)
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.red.opacity(0.85))
        .cornerRadius(12)
        .padding()
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private func pageRow(_ page: MedicalBillPage) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Page \(page.pageNumber)")
                    .font(.subheadline)
                    .bold()
                Text("\(page.overlappingCodes.count) Overlaps Found")
                    .font(.caption2)
                    .foregroundColor(page.overlappingCodes.isEmpty ? .secondary : .red)
            }
            Spacer()
            HStack(spacing: 6) {
                codeCount(page.identifiedDiagnosticCodes.count, label: "DX", color: Brand.diagnosis)
                codeCount(page.identifiedProcedureCodes.count, label: "PX", color: Brand.procedure)
            }
        }
    }

    private func codeCount(_ count: Int, label: String, color: Color) -> some View {
        Text("\(count) \(label)")
            .font(.caption.weight(.semibold))
            .monospacedDigit()
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }

    private func anomalyRow(_ anomaly: BillCodeAnalyzer.Anomaly) -> some View {
        let pages = anomaly.pageNumbers.map(String.init).joined(separator: ", ")
        let color = anomaly.kind == .duplicateProcedure ? Brand.procedure : Brand.diagnosis
        return VStack(alignment: .leading, spacing: 4) {
            Text(anomaly.code)
                .font(.system(.subheadline, design: .monospaced).bold())
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(color.opacity(0.18), in: RoundedRectangle(cornerRadius: 5))
                .foregroundStyle(color)
            switch anomaly.kind {
            case .duplicateProcedure:
                Text("Procedure code billed on pages \(pages)")
                    .font(.caption).foregroundStyle(.secondary)
            case .unlinkedDiagnosis:
                Text("Diagnosis on pages \(pages), with no procedure code on at least one of them")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func finish() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}
