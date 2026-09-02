//
//  DocumentOCR.swift
//  BillGuardCore
//
//  Cross-platform (macOS + iOS) text recognition for a region of a document
//  image. Works on CGImage so it needs no UIKit/VisionKit — the macOS app feeds
//  it images/PDF pages, the iOS app can adopt it later. Mirrors the iOS
//  BillScannerView row-grouping so the OCR strings match what BillParser expects.
//

import Foundation
import Vision
import CoreImage
import CoreGraphics

public enum DocumentOCR {

    /// Recognize text inside a normalized region (0…1, top-left origin) of `cgImage`.
    /// Blocks are grouped into rows by vertical proximity and joined left-to-right,
    /// producing the same line structure the bill parser is tuned for.
    public static func recognizeText(in cgImage: CGImage,
                                     normalizedRegion region: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)) async -> String {
        let w = CGFloat(cgImage.width), h = CGFloat(cgImage.height)
        let pixelRegion = CGRect(x: region.minX * w, y: region.minY * h,
                                 width: region.width * w, height: region.height * h)
        let bounds = CGRect(x: 0, y: 0, width: w, height: h)
        let valid = pixelRegion.intersection(bounds)
        guard !valid.isEmpty, valid.width > 1, valid.height > 1,
              let cropped = cgImage.cropping(to: valid) else { return "" }

        let prepared = prepareForOCR(cropped)

        return await withCheckedContinuation { continuation in
            // Resume exactly once: Vision can both invoke the completion handler
            // (with an error / nil results) AND have perform() throw, which would
            // otherwise resume the continuation twice and crash.
            let resumed = ResumeGuard()
            func finish(_ s: String) { if resumed.take() { continuation.resume(returning: s) } }

            let request = VNRecognizeTextRequest { request, _ in
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    finish(""); return
                }

                struct TextBlock { let text: String; let midX: CGFloat; let midY: CGFloat; let height: CGFloat }

                let blocks: [TextBlock] = observations.compactMap { o in
                    guard let text = o.topCandidates(1).first?.string else { return nil }
                    return TextBlock(text: text, midX: o.boundingBox.midX,
                                     midY: o.boundingBox.midY, height: o.boundingBox.height)
                }

                // Group into rows by Y proximity (Vision Y is bottom-up)
                var rows: [[TextBlock]] = []
                for block in blocks.sorted(by: { $0.midY > $1.midY }) {
                    let yTol = max(block.height * 1.0, 0.012)
                    if let idx = rows.firstIndex(where: { row in
                        let avgY = row.map { $0.midY }.reduce(0, +) / CGFloat(row.count)
                        return abs(avgY - block.midY) < yTol
                    }) {
                        rows[idx].append(block)
                    } else {
                        rows.append([block])
                    }
                }
                rows.sort {
                    ($0.map { $0.midY }.reduce(0, +) / CGFloat($0.count)) >
                    ($1.map { $0.midY }.reduce(0, +) / CGFloat($1.count))
                }

                let lines = rows.map { row in
                    row.sorted { $0.midX < $1.midX }.map { $0.text }.joined(separator: "  ")
                }
                finish(lines.joined(separator: "\n"))
            }
            // Use .fast, not .accurate: the .accurate model is the Neural-Engine
            // "latincyrillic" model, which fails to load under the macOS App Sandbox
            // (loadModel:sandboxExtension:… times out → ~30s hang, zero results).
            // .fast uses a separate model that loads reliably and is quick (~0.3s),
            // and its output parses cleanly for printed bills.
            request.recognitionLevel = .fast
            request.usesLanguageCorrection = true
            do {
                try VNImageRequestHandler(cgImage: prepared, options: [:]).perform([request])
            } catch {
                finish("")
            }
        }
    }

    /// One-shot latch so a continuation is resumed at most once.
    private final class ResumeGuard {
        private var used = false
        func take() -> Bool { if used { return false }; used = true; return true }
    }

    // MARK: - Dark-background pre-processing (verbatim from iOS)

    private static func meanLuminance(of cgImage: CGImage) -> CGFloat {
        guard let data = cgImage.dataProvider?.data, let ptr = CFDataGetBytePtr(data) else { return 0.5 }
        let width = cgImage.width, height = cgImage.height
        let bpp = cgImage.bitsPerPixel / 8, rowBytes = cgImage.bytesPerRow, step = 8
        var total: UInt64 = 0, count: UInt64 = 0, y = 0
        while y < height {
            var x = 0
            while x < width {
                let offset = y * rowBytes + x * bpp
                total &+= UInt64(ptr[offset + min(1, bpp - 1)])
                count &+= 1
                x += step
            }
            y += step
        }
        return count > 0 ? CGFloat(total) / CGFloat(count) / 255.0 : 0.5
    }

    /// Inverts + contrast-boosts dark-background regions so Vision sees dark-on-white.
    private static func prepareForOCR(_ cgImage: CGImage) -> CGImage {
        guard meanLuminance(of: cgImage) < 0.45 else { return cgImage }
        let ci = CIImage(cgImage: cgImage)
        let ctx = CIContext()
        guard let invert = CIFilter(name: "CIColorInvert") else { return cgImage }
        invert.setValue(ci, forKey: kCIInputImageKey)
        guard let inverted = invert.outputImage else { return cgImage }
        guard let contrast = CIFilter(name: "CIColorControls") else { return cgImage }
        contrast.setValue(inverted, forKey: kCIInputImageKey)
        contrast.setValue(1.6, forKey: kCIInputContrastKey)
        contrast.setValue(0.0, forKey: kCIInputSaturationKey)
        guard let boosted = contrast.outputImage else { return cgImage }
        return ctx.createCGImage(boosted, from: boosted.extent) ?? cgImage
    }
}
