//
//  SharedInputLoader.swift
//  BillGuardShare
//
//  Turns whatever the browser shared (PDF, image, text, link) into page texts.
//  A share extension only ever sees the items handed to it at launch, so each
//  share contributes the pages it contains and nothing else.
//

import Foundation
import UniformTypeIdentifiers

struct SharedInput: Sendable {
    var sourceURL: String?
    var pageTexts: [String] = []
    /// True when the share held a PDF or image, whether or not text was found.
    var hadDocument = false
}

@MainActor
enum SharedInputLoader {

    /// Shared plain text shorter than this is a page title, not a bill page.
    private static let minimumTextPageLength = 80

    static func load(from context: NSExtensionContext?) async -> SharedInput {
        let items = (context?.inputItems as? [NSExtensionItem]) ?? []
        let providers = items.flatMap { $0.attachments ?? [] }

        var input = SharedInput()
        var plainTexts: [String] = []

        for provider in providers {
            let identifiers = provider.registeredTypeIdentifiers
            if let pdfID = identifiers.first(where: { conforms($0, to: .pdf) }) {
                input.hadDocument = true
                if let data = await loadData(provider, typeIdentifier: pdfID) {
                    input.pageTexts += await PageOCR.texts(fromPDFData: data)
                }
            } else if let imageID = identifiers.first(where: { conforms($0, to: .image) }) {
                input.hadDocument = true
                if let data = await loadData(provider, typeIdentifier: imageID),
                   let text = await PageOCR.text(fromImageData: data) {
                    input.pageTexts.append(text)
                }
            } else if identifiers.contains(where: { conforms($0, to: .url) }) {
                // Links are kept as the bill's source; the page itself is not fetched.
                if let url = await loadURL(provider), let scheme = url.scheme?.lowercased(),
                   scheme == "http" || scheme == "https" {
                    input.sourceURL = input.sourceURL ?? url.absoluteString
                }
            } else if let textID = identifiers.first(where: { conforms($0, to: .plainText) }) {
                if let data = await loadData(provider, typeIdentifier: textID),
                   let text = String(data: data, encoding: .utf8) {
                    plainTexts.append(text)
                }
            }
        }

        // Selected text counts as a page only when no document came with it.
        if !input.hadDocument {
            input.pageTexts += plainTexts.filter {
                $0.trimmingCharacters(in: .whitespacesAndNewlines).count >= minimumTextPageLength
            }
        }
        return input
    }

    private static func conforms(_ identifier: String, to type: UTType) -> Bool {
        UTType(identifier)?.conforms(to: type) ?? false
    }

    private static func loadData(_ provider: NSItemProvider, typeIdentifier: String) async -> Data? {
        await withCheckedContinuation { continuation in
            _ = provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }

    private static func loadURL(_ provider: NSItemProvider) async -> URL? {
        guard provider.canLoadObject(ofClass: URL.self) else { return nil }
        return await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                continuation.resume(returning: url)
            }
        }
    }
}
