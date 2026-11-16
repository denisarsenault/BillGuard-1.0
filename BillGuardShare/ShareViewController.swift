//
//  ShareViewController.swift
//  BillGuardShare
//
//  Share extension entry point: hosts the SwiftUI scanner view.
//

import UIKit
import SwiftUI

final class ShareViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()

        // Match the app before SwiftUI draws: dark, deep-navy ground (no white flash).
        overrideUserInterfaceStyle = .dark
        view.backgroundColor = UIColor(named: "BrandDeepNavy")

        let host = UIHostingController(rootView: ExtensionContentView(extensionContext: extensionContext))
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        host.didMove(toParent: self)
    }
}
