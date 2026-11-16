//
//  PageOCR.swift
//  BillGuardShare
//
//  Local Vision OCR for shared images and PDFs (spec section 5). Takes Data so
//  the work can run off the main actor; nothing leaves the device.
//

import Foundation
import Vision
import ImageIO
import PDFKit
import CoreGraphics

enum PageOCR {

    /// Longest edge handed to Vision. Keeps the extension inside its memory cap.
    private static let maxPixelSize = 2400

    /// OCR one shared image. Returns nil when the data is not a readable image.
    static func text(fromImageData data: Data) async -> String? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }
        return recognize(image)
    }

    /// OCR every page of a shared PDF, one text per page, in page order.
    static func texts(fromPDFData data: Data) async -> [String] {
        guard let document = PDFDocument(data: data) else { return [] }
        var texts: [String] = []
        for index in 0..<document.pageCount {
            let text: String = autoreleasepool {
                guard let page = document.page(at: index) else { return "" }
                let bounds = page.bounds(for: .mediaBox)
                let longest = max(bounds.width, bounds.height)
                guard longest > 0 else { return "" }
                let scale = CGFloat(maxPixelSize) / longest
                let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
                guard let image = page.thumbnail(of: size, for: .mediaBox).cgImage else { return "" }
                return recognize(image)
            }
            texts.append(text)
        }
        return texts
    }

    private static func recognize(_ image: CGImage) -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        // Language correction rewrites tokens like "E11.9" into words.
        request.usesLanguageCorrection = false
        do {
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        } catch {
            return ""
        }

        // Group observations into rows (Vision Y is bottom-up), left to right.
        struct Block { let text: String; let minX: CGFloat; let midY: CGFloat; let height: CGFloat }
        let blocks: [Block] = (request.results ?? []).compactMap { observation in
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            let box = observation.boundingBox
            return Block(text: text, minX: box.minX, midY: box.midY, height: box.height)
        }
        var rows: [[Block]] = []
        for block in blocks.sorted(by: { $0.midY > $1.midY }) {
            if let last = rows.indices.last, let anchor = rows[last].first,
               abs(anchor.midY - block.midY) < max(anchor.height * 0.6, 0.008) {
                rows[last].append(block)
            } else {
                rows.append([block])
            }
        }
        return rows
            .map { $0.sorted { $0.minX < $1.minX }.map(\.text).joined(separator: "  ") }
            .joined(separator: "\n")
    }
}
