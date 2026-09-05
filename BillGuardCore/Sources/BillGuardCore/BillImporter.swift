//
//  BillImporter.swift
//  BillGuardCore
//
//  Turns a BillParseResult (from a scan or a web capture) into a saved Patient +
//  Claim in the shared data layer. Model construction lives here in the package so
//  callers (macOS app, browser-capture bridge) don't need public model inits.
//

import Foundation

public enum BillImporter {

    /// Save a parsed bill: find-or-create the patient, build the claim (charges +
    /// insurer/patient credits), and persist via PatientDataService. Returns the
    /// resolved patient id and new claim id.
    @MainActor
    @discardableResult
    public static func saveScannedBill(_ r: BillParseResult,
                                       into service: PatientDataService = .shared) -> (patientId: String, claimId: String) {
        // ── Patient: reuse an existing one by name, else create ──
        let fullName = r.patientName.trimmingCharacters(in: .whitespacesAndNewlines)
        let patient: Patient
        if !fullName.isEmpty,
           let existing = service.patients.first(where: { $0.displayName.lowercased() == fullName.lowercased() }) {
            patient = existing
        } else {
            let parts = fullName.split(separator: " ").map(String.init)
            let first = parts.first ?? "Unknown"
            let last  = parts.count > 1 ? parts.dropFirst().joined(separator: " ") : ""
            var addresses: [PatientAddress] = []
            if !r.patientAddress.isEmpty {
                addresses.append(PatientAddress(label: .home, street1: r.patientAddress, isPrimary: true))
            }
            let p = Patient(guardianUserId: UserManager.shared.currentUser?.id ?? "",
                            firstName: first.isEmpty ? "Unknown" : first, lastName: last,
                            addresses: addresses)
            service.savePatient(p)
            patient = p
        }

        // ── Insurance: find-or-create carrier + policy for the patient ──
        var resolvedPolicyId = r.policyNumber.isEmpty ? r.memberId : r.policyNumber
        let hasInsurance = !r.insuranceCarrier.isEmpty || !r.policyNumber.isEmpty || !r.memberId.isEmpty
        if hasInsurance {
            let carrierName = r.insuranceCarrier.isEmpty ? "Insurance" : r.insuranceCarrier
            let carrier: InsuranceCarrier
            if let existing = service.insuranceCarriers.first(where: { $0.name.lowercased() == carrierName.lowercased() }) {
                carrier = existing
            } else {
                let c = InsuranceCarrier(name: carrierName)
                service.saveCarrier(c)
                carrier = c
            }

            let existingPolicy = service.insurancePolicies.first(where: {
                $0.patientId == patient.id && $0.carrierId == carrier.id &&
                (r.memberId.isEmpty || $0.memberId.lowercased() == r.memberId.lowercased())
            })
            if let existingPolicy {
                resolvedPolicyId = existingPolicy.id
            } else {
                let noPrimaryYet = !service.policies(for: patient.id).contains { $0.isPrimary }
                let policy = InsurancePolicy(
                    patientId: patient.id,
                    carrierId: carrier.id,
                    planType: PlanType(rawValue: r.insurancePlanType),
                    planName: r.insurancePlanType.isEmpty ? nil : r.insurancePlanType,
                    memberId: r.memberId,
                    groupNumber: r.groupNumber.isEmpty ? nil : r.groupNumber,
                    policyNumber: r.policyNumber.isEmpty ? nil : r.policyNumber,
                    isPrimary: noPrimaryYet)
                service.savePolicy(policy)
                resolvedPolicyId = policy.id
            }
        }

        // ── Charges → line items + code lists ──
        let chargeItems = r.lineItems.filter { $0.kind == .charge && $0.isSelected }
        let billLineItems: [BillLineItem] = chargeItems.map { item in
            BillLineItem(procedureCode: item.code.isEmpty ? nil : item.code,
                         procedureDescription: item.bestDescription,
                         serviceDate: r.serviceDate, quantity: 1,
                         unitCharge: item.amount, totalCharge: item.amount,
                         notes: item.databasePriceRange.map { "Typical range: \($0)" })
        }
        let cptCodes = chargeItems.compactMap { i -> String? in
            guard !i.code.isEmpty else { return nil }
            if let t = i.codeType { return (t == .cpt || t == .hcpcs) ? i.code : nil }
            return i.code.first?.isNumber == true ? i.code : nil
        }
        let diagCodes = chargeItems.compactMap { i -> String? in
            guard !i.code.isEmpty, let t = i.codeType else { return nil }
            return (t == .icd10 || t == .icd10pcs) ? i.code : nil
        }

        // ── Credits → insurance vs patient payments ──
        let credits = r.lineItems.filter { $0.kind == .payment && abs($0.amount) > 0 }
        func isSelfPay(_ s: String) -> Bool { let l = s.lowercased(); return l.contains("self") || l.contains("card") }
        let insurancePayments = credits.filter { !isSelfPay($0.description) }.map {
            InsurancePayment(payerName: r.insuranceCarrier.isEmpty ? "Insurance" : r.insuranceCarrier,
                             amount: abs($0.amount), paymentDate: r.serviceDate,
                             transactionType: .other,
                             notes: $0.description.isEmpty ? "Payment / Credit" : $0.description)
        }
        let patientPayments = credits.filter { isSelfPay($0.description) }.map {
            PatientPayment(amount: abs($0.amount), paymentDate: r.serviceDate,
                           paymentMethod: .creditCard, confirmationNumber: nil,
                           paidToProvider: r.providerName.isEmpty ? nil : r.providerName,
                           notes: $0.description.isEmpty ? "Self-Pay / Card Payment" : $0.description)
        }

        let chargesSum = chargeItems.reduce(0) { $0 + $1.amount }
        let billed = Double(r.billedAmount) ?? chargesSum
        let due    = Double(r.amountDue) ?? billed

        let claim = Claim(
            patientId: patient.id,
            policyId: resolvedPolicyId,
            providerName: r.providerName.isEmpty ? nil : r.providerName,
            claimNumber: r.accountNumber.isEmpty ? nil : r.accountNumber,
            status: .notSubmitted,
            serviceDate: r.serviceDate,
            billedAmount: billed,
            patientResponsibility: due,
            procedureCodes: cptCodes.isEmpty ? nil : cptCodes,
            diagnosisCodes: diagCodes.isEmpty ? nil : diagCodes,
            lineItems: billLineItems,
            insurancePayments: insurancePayments,
            patientPayments: patientPayments.isEmpty ? nil : patientPayments)
        service.saveClaim(claim)
        return (patient.id, claim.id)
    }
}
