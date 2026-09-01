//
//  ScanDocumentView.swift
//  BillGuard (macOS)
//
//  Import an image or PDF, position the four section boxes, and run the SHARED
//  BillGuardCore pipeline (DocumentOCR → BillParser) — the same parsing as iOS,
//  just sourced from a file instead of the camera.
//

import SwiftUI
import BillGuardCore
import UniformTypeIdentifiers

enum RegionKind: String, CaseIterable, Identifiable {
    case provider = "Provider", patient = "Patient", insurance = "Insurance", procedure = "Procedures"
    var id: String { rawValue }
    var color: Color {
        switch self {
        case .provider: return .green
        case .patient: return .blue
        case .insurance: return .purple
        case .procedure: return .orange
        }
    }
    /// Default box (normalized, top-left origin) mirroring the iOS defaults.
    var defaultRect: CGRect {
        switch self {
        case .provider:  return CGRect(x: 0.02, y: 0.02, width: 0.96, height: 0.16)
        case .patient:   return CGRect(x: 0.02, y: 0.20, width: 0.46, height: 0.16)
        case .insurance: return CGRect(x: 0.52, y: 0.20, width: 0.46, height: 0.16)
        case .procedure: return CGRect(x: 0.02, y: 0.40, width: 0.96, height: 0.55)
        }
    }
}

struct ScanDocumentView: View {
    @State private var image: CGImage?
    @State private var rects: [RegionKind: CGRect] = Dictionary(uniqueKeysWithValues: RegionKind.allCases.map { ($0, $0.defaultRect) })
    @State private var enabled: Set<RegionKind> = Set(RegionKind.allCases)
    @State private var isImporting = false
    @State private var isExtracting = false
    @State private var result: BillParseResult?

    var body: some View {
        Group {
            if let image {
                editor(image)
            } else {
                dropZone
            }
        }
        .navigationTitle("Scan Document")
        .toolbar {
            if image != nil {
                ToolbarItemGroup {
                    Button("Reset Boxes") { rects = Dictionary(uniqueKeysWithValues: RegionKind.allCases.map { ($0, $0.defaultRect) }) }
                    Button("New Document") { image = nil; result = nil }
                    Button {
                        Task { await extract() }
                    } label: { Label("Extract Text", systemImage: "text.viewfinder") }
                    .keyboardShortcut(.return, modifiers: [.command])
                    .disabled(isExtracting)
                }
            } else {
                ToolbarItem { Button("Choose File…") { isImporting = true } }
            }
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: DocumentLoader.acceptedTypes) { res in
            if case .success(let url) = res { load(url) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .scanDocumentRequested)) { _ in isImporting = true }
        .sheet(item: Binding(get: { result.map { ResultBox(value: $0) } }, set: { result = $0?.value })) { box in
            ScanReviewView(result: box.value) { result = nil }
        }
    }

    // MARK: - Drop zone

    private var dropZone: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.badge.arrow.up").font(.system(size: 52)).foregroundStyle(.tint)
            Text("Import a Bill").font(.title2.bold())
            Text("Drag an image or PDF here, or choose a file. It's processed with the same on-device text recognition and parsing as the iOS app — no camera needed.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 440)
            Button("Choose File…") { isImporting = true }.controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            guard let p = providers.first else { return false }
            _ = p.loadObject(ofClass: URL.self) { url, _ in
                if let url { DispatchQueue.main.async { load(url) } }
            }
            return true
        }
    }

    // MARK: - Editor

    private func editor(_ img: CGImage) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("Position boxes over each section").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                ForEach(RegionKind.allCases) { kind in
                    Toggle(isOn: Binding(
                        get: { enabled.contains(kind) },
                        set: { if $0 { enabled.insert(kind) } else { enabled.remove(kind) } })) {
                        Text(kind.rawValue).font(.caption)
                    }
                    .toggleStyle(.button).tint(kind.color)
                }
            }
            .padding(8)

            GeometryReader { geo in
                let fit = aspectFit(CGSize(width: img.width, height: img.height), in: geo.size)
                ZStack(alignment: .topLeading) {
                    Image(img, scale: 1, label: Text("Document"))
                        .resizable().scaledToFit()
                        .frame(width: geo.size.width, height: geo.size.height)
                    ForEach(RegionKind.allCases.filter { enabled.contains($0) }) { kind in
                        RegionBoxView(rect: Binding(
                            get: { rects[kind] ?? kind.defaultRect },
                            set: { rects[kind] = $0 }), fit: fit, color: kind.color, label: kind.rawValue)
                    }
                }
                .overlay(alignment: .center) {
                    if isExtracting { ProgressView("Reading document…").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10)) }
                }
            }
            .background(Color.black.opacity(0.9))
        }
    }

    // MARK: - Actions

    private func load(_ url: URL) {
        if let cg = DocumentLoader.cgImage(from: url) { image = cg; result = nil }
    }

    private func extract() async {
        guard let image else { return }
        isExtracting = true
        func ocr(_ kind: RegionKind) async -> String {
            guard enabled.contains(kind) else { return "" }
            return await DocumentOCR.recognizeText(in: image, normalizedRegion: rects[kind] ?? kind.defaultRect)
        }
        let provider = await ocr(.provider)
        let patient = await ocr(.patient)
        let insurance = await ocr(.insurance)
        let procedure = await ocr(.procedure)
        let parsed = BillParser(patientText: patient, providerText: provider,
                                insuranceText: insurance, procedureText: procedure,
                                lookup: { MedicalCodeDatabase.lookup($0) }).parse()
        await MainActor.run { result = parsed; isExtracting = false }
    }

    private func aspectFit(_ imageSize: CGSize, in container: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        let s = min(container.width / imageSize.width, container.height / imageSize.height)
        let w = imageSize.width * s, h = imageSize.height * s
        return CGRect(x: (container.width - w) / 2, y: (container.height - h) / 2, width: w, height: h)
    }
}

/// Sheet needs Identifiable; wrap the value-type result.
private struct ResultBox: Identifiable { let id = UUID(); let value: BillParseResult }

// MARK: - Draggable / resizable region box

private struct RegionBoxView: View {
    @Binding var rect: CGRect          // normalized, top-left origin
    let fit: CGRect                    // displayed image frame in view coords
    let color: Color
    let label: String

    @State private var startRect: CGRect?
    @State private var startSize: CGSize?

    var body: some View {
        let frame = CGRect(x: fit.minX + rect.minX * fit.width,
                           y: fit.minY + rect.minY * fit.height,
                           width: rect.width * fit.width,
                           height: rect.height * fit.height)
        ZStack(alignment: .topLeading) {
            Rectangle().stroke(color, lineWidth: 2).background(color.opacity(0.12))
            Text(label).font(.caption2.bold()).padding(.horizontal, 5).padding(.vertical, 2)
                .background(color).foregroundStyle(.white).cornerRadius(3).padding(3)
            Circle().fill(color).overlay(Circle().stroke(.white, lineWidth: 1))
                .frame(width: 14, height: 14)
                .position(x: frame.width, y: frame.height)
                .highPriorityGesture(DragGesture()
                    .onChanged { v in
                        let s = startSize ?? rect.size
                        if startSize == nil { startSize = rect.size }
                        let nw = max(0.05, min(1 - rect.minX, s.width + v.translation.width / fit.width))
                        let nh = max(0.05, min(1 - rect.minY, s.height + v.translation.height / fit.height))
                        rect.size = CGSize(width: nw, height: nh)
                    }
                    .onEnded { _ in startSize = nil })
        }
        .frame(width: frame.width, height: frame.height)
        .position(x: frame.midX, y: frame.midY)
        .gesture(DragGesture()
            .onChanged { v in
                let s = startRect ?? rect
                if startRect == nil { startRect = rect }
                var r = s
                r.origin.x = min(max(0, s.minX + v.translation.width / fit.width), 1 - s.width)
                r.origin.y = min(max(0, s.minY + v.translation.height / fit.height), 1 - s.height)
                rect = r
            }
            .onEnded { _ in startRect = nil })
    }
}
