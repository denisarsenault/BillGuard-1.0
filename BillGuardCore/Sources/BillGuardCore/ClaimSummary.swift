//
//  ClaimSummary.swift
//  BillGuardCore
//
//  A public, display-ready projection of a Claim, so UI (the macOS app) can render
//  a bill without exposing every internal model member.
//

import Foundation

public struct ClaimSummary {
    public struct LineItem: Identifiable {
        public let id = UUID()
        public let code: String
        public let description: String
        public let amount: Double
    }
    public struct Payment: Identifiable {
        public let id = UUID()
        public let label: String
        public let amount: Double
    }

    public let claimId: String
    public let providerName: String
    public let claimNumber: String
    public let serviceDate: Date
    public let statusLabel: String
    public let billedAmount: Double
    public let patientResponsibility: Double
    public let charges: [LineItem]
    public let insurancePayments: [Payment]
    public let patientPayments: [Payment]

    public var chargesTotal: Double { charges.reduce(0) { $0 + $1.amount } }
    public var insurancePaidTotal: Double { insurancePayments.reduce(0) { $0 + $1.amount } }
    public var patientPaidTotal: Double { patientPayments.reduce(0) { $0 + $1.amount } }
}

public extension Claim {
    /// Display-ready projection of this claim.
    var summary: ClaimSummary {
        ClaimSummary(
            claimId: id,
            providerName: providerName ?? "",
            claimNumber: claimNumber ?? "",
            serviceDate: serviceDate,
            statusLabel: status.rawValue,
            billedAmount: billedAmount,
            patientResponsibility: patientResponsibility ?? billedAmount,
            charges: lineItems.map {
                .init(code: $0.procedureCode ?? "", description: $0.procedureDescription, amount: $0.totalCharge)
            },
            insurancePayments: insurancePayments.map {
                .init(label: ($0.notes?.isEmpty == false ? $0.notes! : $0.payerName), amount: $0.amount)
            },
            patientPayments: (patientPayments ?? []).map {
                .init(label: ($0.notes?.isEmpty == false ? $0.notes! : "Patient Payment"), amount: $0.amount)
            })
    }
}
