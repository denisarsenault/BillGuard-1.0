//
//  ShareViewController.swift
//  BillGuardShareMac
//
//  macOS share extension entry point: hosts the same SwiftUI scanner view as
//  the iOS extension (sources shared from ../BillGuardShare).
//

import AppKit
import SwiftUI

final class ShareViewController: NSViewController {

    override func loadView() {
        let host = NSHostingView(rootView: ExtensionContentView(extensionContext: extensionContext))
        // Match the app: dark only.
        host.appearance = NSAppearance(named: .darkAqua)
        view = host
        preferredContentSize = NSSize(width: 460, height: 600)
    }
}
