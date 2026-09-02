//
//  DocumentLoader.swift
//  BillGuard (macOS)
//
//  Loads a CGImage from an imported image or PDF file (no camera on Mac).
//

import Foundation
import CoreGraphics
import ImageIO
import PDFKit
import UniformTypeIdentifiers

enum DocumentLoader {
    /// Content types accepted by the file importer / drag-drop.
    static let acceptedTypes: [UTType] = [.image, .pdf]

    /// Produce a CGImage from a file URL (first page for PDFs).
    ///
    /// Reads the whole file into memory WHILE the security-scoped access is held —
    /// otherwise a lazily-decoded CGImage would try to read the file later (after
    /// the scope is released) and hit a sandbox "Operation not permitted".
    static func cgImage(from url: URL) -> CGImage? {
        let needsScope = url.startAccessingSecurityScopedResource()
        defer { if needsScope { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }

        let isPDF = url.pathExtension.lowercased() == "pdf"
            || UTType(filenameExtension: url.pathExtension) == .pdf
        if isPDF { return pdfFirstPage(data) }

        // Force a fully-decoded, memory-backed image so nothing touches the file later.
        let opts: [CFString: Any] = [kCGImageSourceShouldCacheImmediately: true]
        if let src = CGImageSourceCreateWithData(data as CFData, nil),
           let image = CGImageSourceCreateImageAtIndex(src, 0, opts as CFDictionary) {
            return image
        }
        return pdfFirstPage(data)   // last-ditch (some PDFs lack .pdf extension)
    }

    private static func pdfFirstPage(_ data: Data, targetWidth: CGFloat = 2000) -> CGImage? {
        guard let doc = PDFDocument(data: data), let page = doc.page(at: 0) else { return nil }
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0 else { return nil }
        let scale = targetWidth / bounds.width
        let w = Int(bounds.width * scale), h = Int(bounds.height * scale)
        guard w > 0, h > 0,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.scaleBy(x: scale, y: scale)
        page.draw(with: .mediaBox, to: ctx)
        return ctx.makeImage()
    }
}
