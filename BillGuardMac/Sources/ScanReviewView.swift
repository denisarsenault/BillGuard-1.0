//
//  ScanReviewView.swift
//  BillGuard (macOS)
//
//  Read-only review of a parsed bill (BillParseResult) from the shared parser,
//  saved through BillImporter. Also the sheet that adds a saved share-extension
//  scan ("Web Captures") to Bills.
//

import SwiftUI
import BillGuardCore

struct ScanReviewView: View {
    let result: BillParseResult
    var onClose: () -> Void
    var title = "Review Bill"
    /// Save for this patient, instead of finding or creating one from the
    /// name on the bill.
    var patientId: String? = nil
    var canSave = true
    /// Shown between the title bar and the bill (the patient picker, when a
    /// saved scan is being added).
    var accessory: AnyView? = nil
    /// Called after the bill is saved, before `onClose`.
    var onSaved: (() -> Void)? = nil

    @State private var isSaved = false

    private var charges: [ParsedLineItem] { result.lineItems.filter { $0.kind == .charge } }
    private var credits: [ParsedLineItem] { result.lineItems.filter { $0.kind == .payment } }
    private var chargesTotal: Double { charges.reduce(0) { $0 + $1.amount } }
    private var creditsTotal: Double { credits.reduce(0) { $0 + $1.amount } }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(.title2.bold())
                Spacer()
                Button("Cancel") { onClose() }
                Button(isSaved ? "Saved ✓" : "Save Bill") {
                    _ = BillImporter.saveScannedBill(result, forPatientId: patientId)
                    isSaved = true
                    onSaved?()
                    onClose()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(isSaved || !canSave)
            }
            .padding()

            if let accessory { accessory }

            Form {
                if !result.providerName.isEmpty || !result.providerAddress.isEmpty {
                    Section("Provider") {
                        row("Facility", result.providerName)
                        row("Address", result.providerAddress)
                        row("Phone", result.providerPhone)
                        row("Fax", result.providerFax)
                    }
                }
                Section("Patient") {
                    row("Name", result.patientName)
                    row("Account #", result.accountNumber)
                    row("MRN", result.mrn)
                    row("Date of Birth", result.dateOfBirth)
                    row("Service Date", result.serviceDate.formatted(date: .abbreviated, time: .omitted))
                }
                if !result.insuranceCarrier.isEmpty || !result.policyNumber.isEmpty {
                    Section("Insurance") {
                        row("Carrier", result.insuranceCarrier)
                        row("Policy #", result.policyNumber)
                        row("Member ID", result.memberId)
                        row("Plan Type", result.insurancePlanType)
                    }
                }

                Section("Charges (\(charges.count))") {
                    ForEach(charges) { item in
                        HStack {
                            if !item.code.isEmpty {
                                Text(item.code).font(.system(.caption, design: .monospaced).bold())
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(.tint.opacity(0.15)).cornerRadius(4)
                            }
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.bestDescription)
                                if let range = item.databasePriceRange {
                                    Text("Typical: \(range)").font(.caption).foregroundStyle(.green)
                                }
                            }
                            Spacer()
                            Text(item.amount, format: .currency(code: "USD")).monospacedDigit()
                        }
                    }
                    HStack { Text("Charges Total").bold(); Spacer()
                        Text(chargesTotal, format: .currency(code: "USD")).bold().foregroundStyle(.tint) }
                }

                if !credits.isEmpty {
                    Section("Payments & Credits (\(credits.count))") {
                        ForEach(credits) { item in
                            HStack {
                                Image(systemName: "arrow.down.left.circle.fill").foregroundStyle(.green)
                                Text(item.description.isEmpty ? "Payment / Credit" : item.description)
                                Spacer()
                                Text(item.amount, format: .currency(code: "USD"))
                                    .monospacedDigit().foregroundStyle(item.amount < 0 ? .green : .secondary)
                            }
                        }
                        HStack { Text("Payments & Credits").bold(); Spacer()
                            Text(creditsTotal, format: .currency(code: "USD")).bold().foregroundStyle(.green) }
                    }
                }

                Section("Financial Summary") {
                    row("Billed", result.billedAmount)
                    row("Insurance Adjustment", result.insuranceAdjustment)
                    row("Insurance Paid", result.insurancePaid)
                    row("Amount Due", result.amountDue, emphasize: true)
                }
            }
            .formStyle(.grouped)
        }
        .frame(minWidth: 560, minHeight: 640)
    }

    @ViewBuilder private func row(_ label: String, _ value: String, emphasize: Bool = false) -> some View {
        if !value.isEmpty {
            LabeledContent(label) {
                Text(value).foregroundStyle(emphasize ? Color.red : .primary)
                    .fontWeight(emphasize ? .bold : .regular)
            }
        }
    }
}

// MARK: - Adding a saved scan to Bills

/// Opens a saved share-extension scan as a bill. Charges and totals are read
/// from the scan's text by the shared parser; patient and insurance details
/// come from the labelled lines only, and the person picks who the bill is for.
struct SharedScanImportSheet: View {
    let scan: SharedScan
    let finish: (_ saved: Bool) -> Void

    @StateObject private var data = PatientDataService.shared
    @State private var parsed: BillParseResult
    /// A patient's id, `newPatient`, or empty until one is picked.
    @State private var choice: String
    @State private var newPatientName: String

    private static let newPatient = "__new__"

    init(scan: SharedScan, finish: @escaping (_ saved: Bool) -> Void) {
        self.scan = scan
        self.finish = finish

        var result = BillParser(providerText: scan.letterhead,
                                procedureText: scan.fullText,
                                lookup: { MedicalCodeDatabase.lookup($0) }).parse()
        let fields = scan.labelledFields
        result.patientName = fields.patientName
        result.accountNumber = fields.accountNumber
        result.dateOfBirth = fields.dateOfBirth
        result.insuranceCarrier = fields.insuranceCarrier
        result.memberId = fields.memberID
        result.groupNumber = fields.groupNumber
        result.policyNumber = fields.policyNumber
        if let date = fields.serviceDate { result.serviceDate = date }
        _parsed = State(initialValue: result)

        // Preselect the patient named on the bill, or the only patient there is.
        let patients = PatientDataService.shared.patients
        let name = fields.patientName.lowercased()
        let match = patients.first {
            !name.isEmpty && $0.displayName.trimmingCharacters(in: .whitespaces).lowercased() == name
        }
        if let match {
            _choice = State(initialValue: match.id)
        } else if !name.isEmpty || patients.isEmpty {
            _choice = State(initialValue: Self.newPatient)
        } else if patients.count == 1 {
            _choice = State(initialValue: patients[0].id)
        } else {
            _choice = State(initialValue: "")
        }
        _newPatientName = State(initialValue: fields.patientName)
    }

    private var chosenPatient: Patient? { data.patients.first { $0.id == choice } }
    private var trimmedNewName: String { newPatientName.trimmingCharacters(in: .whitespaces) }
    private var canSave: Bool { chosenPatient != nil || (choice == Self.newPatient && !trimmedNewName.isEmpty) }

    /// The bill as it will be saved: under the chosen patient's name.
    private var result: BillParseResult {
        var result = parsed
        result.patientName = chosenPatient?.displayName.trimmingCharacters(in: .whitespaces) ?? trimmedNewName
        return result
    }

    var body: some View {
        ScanReviewView(result: result,
                       onClose: { finish(false) },
                       title: "Add to Bills",
                       patientId: chosenPatient?.id,
                       canSave: canSave,
                       accessory: AnyView(patientBar),
                       onSaved: { finish(true) })
    }

    private var patientBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Picker("Bill for", selection: $choice) {
                    if choice.isEmpty { Text("Choose a patient").tag("") }
                    ForEach(data.patients) { patient in
                        Text(patient.displayName).tag(patient.id)
                    }
                    Divider()
                    Text("New Patient…").tag(Self.newPatient)
                }
                .frame(maxWidth: 300)
                if choice == Self.newPatient {
                    TextField("Patient name", text: $newPatientName)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 240)
                }
                Spacer()
            }
            Text("Read from a saved scan. Check the charges against the bill; anything the scan did not label is left blank.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal)
        .padding(.bottom, 10)
    }
}
