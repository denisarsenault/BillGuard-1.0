//
//  SafariWebExtensionHandler.swift
//  BillGuardWebExtension
//
//  The native end of the Safari Web Extension. Safari hands every
//  `browser.runtime.sendNativeMessage` from Resources/popup.js to this class;
//  the work is done by WebCaptureBridge. Built into the iOS app
//  (BillGuardWebExtension) and the Mac app (BillGuardWebExtensionMac) from
//  the same sources.
//

import Foundation
import SafariServices

final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {

    func beginRequest(with context: NSExtensionContext) {
        let item = context.inputItems.first as? NSExtensionItem
        let request = WebCaptureRequest(message: item?.userInfo?[SFExtensionMessageKey])
        let reply = ReplyChannel(context)

        Task {
            let answer: WebCaptureReply
            if let request {
                answer = await WebCaptureBridge.handle(request)
            } else {
                answer = WebCaptureReply(bill: PendingBillStore().load(),
                                         error: "BillGuard did not understand the request.")
            }
            reply.send(answer.dictionary)
        }
    }
}

/// Carries the extension context into the task that answers it. The context
/// is used once, to complete the request.
private final class ReplyChannel: @unchecked Sendable {
    private let context: NSExtensionContext

    init(_ context: NSExtensionContext) {
        self.context = context
    }

    func send(_ message: [String: Any]) {
        let item = NSExtensionItem()
        item.userInfo = [SFExtensionMessageKey: message]
        context.completeRequest(returningItems: [item], completionHandler: nil)
    }
}
