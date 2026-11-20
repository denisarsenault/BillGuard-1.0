//
//  PageOCR.swift
//  BillGuardShare
//
//  Local Vision OCR for shared images and PDFs (spec section 5). Takes Data so
//  the work can run off the main actor; nothing leaves the device. Shared by
//  the iOS and macOS share extensions.
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
        #if os(macOS)
        return recognize(enlargedForFastRecognition(image))
        #else
        return recognize(image)
        #endif
    }

    #if os(macOS)
    /// The Mac's fast recognizer misreads small glyphs (it read "J1885" as
    /// "11885" on a 783 px screenshot), so small images are scaled up first.
    private static func enlargedForFastRecognition(_ image: CGImage) -> CGImage {
        let longest = max(image.width, image.height)
        guard longest > 0, longest < maxPixelSize else { return image }
        let scale = CGFloat(maxPixelSize) / CGFloat(longest)
        let width = Int(CGFloat(image.width) * scale), height = Int(CGFloat(image.height) * scale)
        guard let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return image }
        context.interpolationQuality = .high
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage() ?? image
    }
    #endif

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
                guard let image = render(page, bounds: bounds, scale: CGFloat(maxPixelSize) / longest)
                else { return "" }
                return recognize(image)
            }
            texts.append(text)
        }
        return texts
    }

    /// Draw a PDF page into a bitmap. Core Graphics only, so iOS and macOS share it.
    private static func render(_ page: PDFPage, bounds: CGRect, scale: CGFloat) -> CGImage? {
        let width = Int(bounds.width * scale), height = Int(bounds.height * scale)
        guard width > 0, height > 0,
              let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -bounds.minX, y: -bounds.minY)
        page.draw(with: .mediaBox, to: context)
        return context.makeImage()
    }

    private static func recognize(_ image: CGImage) -> String {
        let request = VNRecognizeTextRequest()
        #if os(macOS)
        // .accurate is unusable on the Mac: it took 55 s on one page here, and
        // hangs under the sandbox (why BillGuardCore's DocumentOCR also uses .fast).
        request.recognitionLevel = .fast
        #else
        request.recognitionLevel = .accurate
        #endif
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
