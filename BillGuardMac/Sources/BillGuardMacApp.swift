//
//  BillGuardMacApp.swift
//  BillGuard
//
//  Medical billing code lookup app
//
//  Native macOS app entry point. Shares its data/model layer with the iOS app
//  via the BillGuardCore Swift package. Unlike iOS there is no live camera —
//  documents are scanned by importing an image or PDF file, and a browser
//  extension captures web-based bill portals into CloudKit.
//

import SwiftUI
import BillGuardCore

@main
struct BillGuardMacApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Scan Document…") {
                    NotificationCenter.default.post(name: .scanDocumentRequested, object: nil)
                }
                .keyboardShortcut("o", modifiers: [.command])
            }
        }
    }
}

extension Notification.Name {
    static let scanDocumentRequested = Notification.Name("BillGuardMac.scanDocumentRequested")
}
