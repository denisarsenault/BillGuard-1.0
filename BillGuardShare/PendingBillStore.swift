//
//  PendingBillStore.swift
//  BillGuardShare
//
//  Holds the pages captured so far between shares. Each share adds a page; the
//  bill stays here until the user commits it to CloudKit or discards it.
//

import Foundation

struct PendingBill: Codable, Sendable {
    var sourceURL: String?
    var pages: [MedicalBillPage] = []
}

struct PendingBillStore {
    static let appGroupID = "group.com.mybrightzone.BillGuard"

    /// The shared App Group container, or the extension's own storage when the
    /// group is not provisioned (pages still persist between shares either way).
    private var fileURL: URL {
        let fileManager = FileManager.default
        let base = fileManager.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupID)
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("PendingMedicalBill.json")
    }

    func load() -> PendingBill {
        guard let data = try? Data(contentsOf: fileURL),
              let bill = try? JSONDecoder().decode(PendingBill.self, from: data)
        else { return PendingBill() }
        return bill
    }

    func save(_ bill: PendingBill) throws {
        let url = fileURL
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try JSONEncoder().encode(bill).write(to: url, options: [.atomic, .completeFileProtection])
    }

    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
