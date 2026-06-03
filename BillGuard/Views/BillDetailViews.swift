//
//  BillDetailViews.swift
//  BillGuard
//
//  Comprehensive bill management screens

import SwiftUI
import Vision
import PhotosUI

// MARK: - Bill Line Item Model

struct BillLineItem: Identifiable, Codable, Hashable {
    var id: String = UUID().uuidString
    var procedureCode: String?
    var procedureDescription: String
    var diagnosisCodes: [String]?
    var modifiers: [String]?
    var serviceDate: Date
    var quantity: Int = 1
    var unitCharge: Double
    var totalCharge: Double
    var allowedAmount: Double?
    var adjustmentAmount: Double?
    var insurancePaid: Double?
    var patientResponsibility: Double?
    var denialCode: String?
    var denialReason: String?
    var notes: String?
    
    init(
        id: String = UUID().uuidString,
        procedureCode: String? = nil,
        procedureDescription: String,
        diagnosisCodes: [String]? = nil,
        modifiers: [String]? = nil,
        serviceDate: Date = Date(),
        quantity: Int = 1,
        unitCharge: Double,
        totalCharge: Double? = nil,
        allowedAmount: Double? = nil,
        adjustmentAmount: Double? = nil,
        insurancePaid: Double? = nil,
        patientResponsibility: Double? = nil,
        denialCode: String? = nil,
        denialReason: String? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.procedureCode = procedureCode
        self.procedureDescription = procedureDescription
        self.diagnosisCodes = diagnosisCodes
        self.modifiers = modifiers
        self.serviceDate = serviceDate
        self.quantity = quantity
        self.unitCharge = unitCharge
        self.totalCharge = totalCharge ?? (Double(quantity) * unitCharge)
        self.allowedAmount = allowedAmount
        self.adjustmentAmount = adjustmentAmount
        self.insurancePaid = insurancePaid
        self.patientResponsibility = patientResponsibility
        self.denialCode = denialCode
        self.denialReason = denialReason
        self.notes = notes
    }
}

// MARK: - Bill Main View

struct BillMainView: View {
    let claim: Claim
    @EnvironmentObject var patientDataService: PatientDataService
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    
    @State private var showingEditView = false
    @State private var showingAddProcedure = false
    @State private var lineItems: [BillLineItem] = []
    @State private var showingPaymentSheet = false
    @State private var showingInsurancePaymentSheet = false
    @State private var showingDisputeSheet = false
    @State private var showingScanner = false
    @State private var showingNoPhoneAlert = false
    
    /// Look up the provider for this claim
    private var claimProvider: Provider? {
        if let providerId = claim.providerId {
            return patientDataService.providers.first { $0.id == providerId }
        }
        if let name = claim.providerName {
            return patientDataService.providers.first { $0.name.lowercased() == name.lowercased() }
        }
        return nil
    }
    
    private var providerPhoneNumber: String? {
        claimProvider?.primaryPhone
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                statusHeader
                financialSummaryCard
                providerCard
                serviceInfoCard
                proceduresSection
                insurancePaymentsSection
                patientPaymentsSection
                if !claim.policyId.isEmpty { insuranceCard }
                if let notes = claim.notes, !notes.isEmpty { notesCard(notes: notes) }
                actionButtons
            }
            .padding()
        }
        .navigationTitle("Bill Details")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            lineItems = claim.lineItems
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button { showingEditView = true } label: {
                        Label("Edit Bill", systemImage: "pencil")
                    }
                    Button { showingAddProcedure = true } label: {
                        Label("Add Procedure", systemImage: "plus")
                    }
                    Divider()
                    Button { showingInsurancePaymentSheet = true } label: {
                        Label("Record Insurance Payment", systemImage: "building.columns")
                    }
                    Button { showingPaymentSheet = true } label: {
                        Label("Record Patient Payment", systemImage: "creditcard")
                    }
                    Divider()
                    Button { showingScanner = true } label: {
                        Label("Scan Document", systemImage: "doc.text.viewfinder")
                    }
                    Divider()
                    Button { } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingEditView) {
            BillDetailEditView(claim: claim)
                .environmentObject(patientDataService)
        }
        .sheet(isPresented: $showingAddProcedure) {
            AddProcedureView(lineItems: $lineItems)
                .environmentObject(appState)
                .onDisappear { saveLineItems() }
        }
        .sheet(isPresented: $showingPaymentSheet) {
            RecordPaymentView(claim: claim)
                .environmentObject(patientDataService)
        }
        .sheet(isPresented: $showingInsurancePaymentSheet) {
            RecordInsurancePaymentView(claim: claim)
                .environmentObject(patientDataService)
        }
        .sheet(isPresented: $showingDisputeSheet) {
            DisputeBillView(claim: claim)
                .environmentObject(patientDataService)
        }
        .alert("No Phone Number", isPresented: $showingNoPhoneAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("No phone number is on file for \(claim.providerName ?? "this provider"). You can add one by editing the provider in the Providers tab.")
        }
        .fullScreenCover(isPresented: $showingScanner) {
            BillDocumentScanner { extractedData in
                // Convert extracted data to line items
                for proc in extractedData.procedures {
                    let item = BillLineItem(
                        procedureCode: proc.code,
                        procedureDescription: proc.description,
                        diagnosisCodes: proc.diagnosisCodes.isEmpty ? nil : proc.diagnosisCodes,
                        modifiers: proc.modifiers.isEmpty ? nil : proc.modifiers,
                        serviceDate: proc.serviceDate,
                        quantity: proc.quantity,
                        unitCharge: proc.unitCost > 0 ? proc.unitCost : proc.totalCost,
                        totalCharge: proc.totalCost
                    )
                    lineItems.append(item)
                }
                
                // Update claim with extracted data if needed
                var updatedClaim = claim
                if updatedClaim.providerName == nil || updatedClaim.providerName?.isEmpty == true {
                    updatedClaim.providerName = extractedData.provider.displayName
                }
                if updatedClaim.billedAmount == 0 && extractedData.totalCharges > 0 {
                    updatedClaim.billedAmount = extractedData.totalCharges
                }
                if updatedClaim.patientResponsibility == nil && extractedData.amountDue > 0 {
                    updatedClaim.patientResponsibility = extractedData.amountDue
                }
                if updatedClaim.paidAmount == nil && extractedData.insurancePaid > 0 {
                    updatedClaim.paidAmount = extractedData.insurancePaid
                }
                if updatedClaim.adjustmentAmount == nil && extractedData.adjustments > 0 {
                    updatedClaim.adjustmentAmount = extractedData.adjustments
                }
                
                updatedClaim.lineItems = lineItems
                patientDataService.saveClaim(updatedClaim)
            }
            .environmentObject(patientDataService)
            .environmentObject(appState)
        }
    }
    
    /// Persist line items back to the claim
    private func saveLineItems() {
        var updated = claim
        updated.lineItems = lineItems
        // Sync procedure codes from line items
        updated.procedureCodes = lineItems.compactMap(\.procedureCode).filter { !$0.isEmpty }
        updated.updatedAt = Date()
        patientDataService.saveClaim(updated)
    }
    
    private var statusHeader: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(claim.providerName ?? "Medical Provider")
                        .font(.title2).fontWeight(.bold)
                    if let num = claim.claimNumber {
                        Text("Bill #\(num)").font(.subheadline).foregroundColor(.secondary)
                    }
                }
                Spacer()
                BillStatusBadge(status: claim.status)
            }
            HStack {
                Image(systemName: "calendar").foregroundColor(.secondary)
                Text("Service Date: \(claim.serviceDate, style: .date)")
                    .font(.subheadline).foregroundColor(.secondary)
                Spacer()
            }
        }
        .padding()
        .background(Color("BrandNavy"))
        .cornerRadius(12)
    }
    
    private var financialSummaryCard: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Financial Summary").font(.headline)
                Spacer()
                if !lineItems.isEmpty {
                    Text("\(lineItems.count) line item\(lineItems.count == 1 ? "" : "s")")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
            VStack(spacing: 12) {
                if !lineItems.isEmpty {
                    BillFinancialRow(label: "Total Charges (\(lineItems.count) items)", amount: claim.lineItemsTotalCharged, style: .regular)
                    if claim.lineItemsTotalAllowed > 0 {
                        BillFinancialRow(label: "Total Allowed", amount: claim.lineItemsTotalAllowed, style: .regular)
                    }
                    if claim.lineItemsTotalAdjustments > 0 {
                        BillFinancialRow(label: "Total Adjustments", amount: -claim.lineItemsTotalAdjustments, style: .adjustment)
                    }
                } else {
                    BillFinancialRow(label: "Total Charges", amount: claim.billedAmount, style: .regular)
                    if let a = claim.allowedAmount { BillFinancialRow(label: "Allowed Amount", amount: a, style: .regular) }
                    if let a = claim.adjustmentAmount { BillFinancialRow(label: "Adjustments", amount: -a, style: .adjustment) }
                }
                
                Divider()
                
                // Insurance payments
                if !claim.insurancePayments.isEmpty {
                    BillFinancialRow(label: "Insurance Paid (\(claim.insurancePaymentCount) payment\(claim.insurancePaymentCount == 1 ? "" : "s"))", amount: -claim.totalInsurancePayments, style: .payment)
                } else if let p = claim.paidAmount {
                    BillFinancialRow(label: "Insurance Paid", amount: -p, style: .payment)
                }
                
                // Patient payments
                if !(claim.patientPayments ?? []).isEmpty {
                    BillFinancialRow(label: "Patient Paid (\(claim.patientPaymentCount) payment\(claim.patientPaymentCount == 1 ? "" : "s"))", amount: -claim.totalPatientPayments, style: .payment)
                }
                
                if let d = claim.deductibleApplied { BillFinancialRow(label: "Applied to Deductible", amount: d, style: .regular) }
                if let c = claim.coinsuranceAmount { BillFinancialRow(label: "Coinsurance", amount: c, style: .regular) }
                if let c = claim.copayAmount { BillFinancialRow(label: "Copay", amount: c, style: .regular) }
                
                Divider()
                
                BillFinancialRow(label: "Running Balance", amount: claim.runningBalance, style: .total)
                BillFinancialRow(label: "Your Responsibility", amount: claim.patientResponsibility ?? claim.runningBalance, style: .total)
            }
        }
        .padding()
        .background(Color("BrandNavy"))
        .cornerRadius(12)
    }
    
    private var providerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("Provider").font(.headline); Spacer() }
            Text(claim.providerName ?? "Unknown Provider").font(.body).fontWeight(.medium)
            if let id = claim.providerId {
                HStack {
                    Text("Provider ID:").foregroundColor(.secondary)
                    Text(id)
                }.font(.caption)
            }
            if let phone = providerPhoneNumber {
                HStack(spacing: 6) {
                    Image(systemName: "phone.fill")
                        .font(.caption)
                        .foregroundColor(Color("BrandCyan"))
                    Text(phone)
                        .font(.caption)
                        .foregroundColor(Color("BrandCyan"))
                }
            }
            if let address = claimProvider?.address {
                HStack(spacing: 6) {
                    Image(systemName: "mappin")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(address.formatted)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color("BrandNavy"))
        .cornerRadius(12)
    }
    
    private var serviceInfoCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("Service Information").font(.headline); Spacer() }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                BillInfoCell(label: "Service Date", value: formatDate(claim.serviceDate))
                if let d = claim.submissionDate { BillInfoCell(label: "Submitted", value: formatDate(d)) }
                if let d = claim.eobDate { BillInfoCell(label: "EOB Received", value: formatDate(d)) }
                if let d = claim.paymentDate { BillInfoCell(label: "Payment Date", value: formatDate(d)) }
            }
        }
        .padding()
        .background(Color("BrandNavy"))
        .cornerRadius(12)
    }
    
    private var proceduresSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Procedures").font(.headline)
                if !lineItems.isEmpty {
                    Text("(\(lineItems.count))")
                        .font(.subheadline).foregroundColor(.secondary)
                }
                Spacer()
                Button { showingAddProcedure = true } label: {
                    Label("Add", systemImage: "plus.circle")
                        .font(.subheadline)
                }
            }
            if lineItems.isEmpty {
                if let codes = claim.procedureCodes, !codes.isEmpty {
                    ForEach(codes, id: \.self) { code in
                        NavigationLink {
                            ProcedureDetailView(procedureCode: code, lineItem: nil).environmentObject(appState)
                        } label: { ProcedureRowSimple(code: code) }
                        .buttonStyle(.plain)
                    }
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "list.bullet.rectangle")
                            .font(.title2).foregroundColor(.secondary)
                        Text("No procedures recorded")
                            .font(.subheadline).foregroundColor(.secondary)
                        Text("Tap + to add up to 300+ billable codes")
                            .font(.caption2).foregroundColor(Color(.tertiaryLabel))
                    }
                    .frame(maxWidth: .infinity).padding()
                }
            } else {
                // Use LazyVStack for performance with 300+ items
                LazyVStack(spacing: 2) {
                    ForEach(lineItems) { item in
                        NavigationLink {
                            ProcedureDetailView(procedureCode: item.procedureCode, lineItem: item).environmentObject(appState)
                        } label: { ProcedureRow(item: item) }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                withAnimation {
                                    lineItems.removeAll { $0.id == item.id }
                                    saveLineItems()
                                }
                            } label: { Label("Delete", systemImage: "trash") }
                        }
                    }
                }
                
                // Line items subtotals
                if lineItems.count > 1 {
                    Divider().padding(.top, 4)
                    HStack {
                        Text("Subtotal (\(lineItems.count) items)")
                            .font(.caption).foregroundColor(.secondary)
                        Spacer()
                        Text(claim.lineItemsTotalCharged, format: .currency(code: "USD"))
                            .font(.caption).fontWeight(.semibold)
                    }
                }
            }
        }
        .padding()
        .background(Color("BrandNavy"))
        .cornerRadius(12)
    }
    
    // MARK: - Insurance Payments Section
    
    private var insurancePaymentsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Insurance Payments").font(.headline)
                if !claim.insurancePayments.isEmpty {
                    Text("(\(claim.insurancePayments.count))")
                        .font(.subheadline).foregroundColor(.secondary)
                }
                Spacer()
                Button { showingInsurancePaymentSheet = true } label: {
                    Label("Add", systemImage: "plus.circle")
                        .font(.subheadline)
                }
            }
            
            if claim.insurancePayments.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "building.columns")
                        .font(.title3).foregroundColor(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("No insurance payments recorded")
                            .font(.subheadline).foregroundColor(.secondary)
                        Text("Track check/EFT payments from insurance")
                            .font(.caption2).foregroundColor(Color(.tertiaryLabel))
                    }
                }
                .padding(.vertical, 8)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(claim.insurancePayments) { payment in
                        InsurancePaymentRow(payment: payment)
                    }
                }
                
                // Running totals
                Divider().padding(.top, 4)
                VStack(spacing: 6) {
                    HStack {
                        Text("Total Insurance Paid")
                            .font(.caption).fontWeight(.medium)
                        Spacer()
                        Text(claim.totalInsurancePayments, format: .currency(code: "USD"))
                            .font(.caption).fontWeight(.semibold).foregroundColor(.green)
                    }
                    HStack {
                        Text("Remaining Balance")
                            .font(.caption).fontWeight(.medium)
                        Spacer()
                        Text(claim.runningBalance, format: .currency(code: "USD"))
                            .font(.caption).fontWeight(.semibold)
                            .foregroundColor(claim.runningBalance > 0 ? .orange : .green)
                    }
                }
            }
        }
        .padding()
        .background(Color("BrandNavy"))
        .cornerRadius(12)
    }
    
    // MARK: - Patient Payments Section
    
    private var patientPaymentsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Patient Payments").font(.headline)
                if !(claim.patientPayments ?? []).isEmpty {
                    Text("(\((claim.patientPayments ?? []).count))")
                        .font(.subheadline).foregroundColor(.secondary)
                }
                Spacer()
                Button { showingPaymentSheet = true } label: {
                    Label("Add", systemImage: "plus.circle")
                        .font(.subheadline)
                }
            }
            
            if (claim.patientPayments ?? []).isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "creditcard")
                        .font(.title3).foregroundColor(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("No patient payments recorded")
                            .font(.subheadline).foregroundColor(.secondary)
                        Text("Record payments you've made to the provider")
                            .font(.caption2).foregroundColor(Color(.tertiaryLabel))
                    }
                }
                .padding(.vertical, 8)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(claim.patientPayments ?? []) { payment in
                        PatientPaymentRow(payment: payment)
                    }
                }
                
                Divider().padding(.top, 4)
                VStack(spacing: 6) {
                    HStack {
                        Text("Total Patient Paid")
                            .font(.caption).fontWeight(.medium)
                        Spacer()
                        Text(claim.totalPatientPayments, format: .currency(code: "USD"))
                            .font(.caption).fontWeight(.semibold).foregroundColor(.green)
                    }
                    HStack {
                        Text("Remaining Balance")
                            .font(.caption).fontWeight(.medium)
                        Spacer()
                        Text(claim.runningBalance, format: .currency(code: "USD"))
                            .font(.caption).fontWeight(.semibold)
                            .foregroundColor(claim.runningBalance > 0 ? .orange : .green)
                    }
                }
            }
        }
        .padding()
        .background(Color("BrandNavy"))
        .cornerRadius(12)
    }
    
    private var insuranceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Insurance").font(.headline)
                Spacer()
                if claim.eobReceived {
                    Label("EOB Received", systemImage: "checkmark.circle.fill").font(.caption).foregroundColor(.green)
                }
            }
            Text("Policy ID: \(claim.policyId)").font(.subheadline)
            HStack {
                Text("Status:").foregroundColor(.secondary)
                Text(claim.status.rawValue).foregroundColor(statusColor(for: claim.status))
            }.font(.subheadline)
            if let r = claim.denialReason {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Denial Reason:").font(.caption).foregroundColor(.secondary)
                    Text(r).font(.caption).foregroundColor(.red)
                }.padding(.top, 4)
            }
        }
        .padding()
        .background(Color("BrandNavy"))
        .cornerRadius(12)
    }
    
    private func notesCard(notes: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Notes").font(.headline)
            Text(notes).font(.subheadline).foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color("BrandNavy"))
        .cornerRadius(12)
    }
    
    private var actionButtons: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                if (claim.patientResponsibility ?? 0) > 0 || claim.runningBalance > 0 {
                    Button { showingPaymentSheet = true } label: {
                        HStack { Image(systemName: "creditcard"); Text("Patient Payment") }
                            .font(.subheadline).fontWeight(.semibold).foregroundColor(.white)
                            .frame(maxWidth: .infinity).padding()
                            .background(Color.green).cornerRadius(12)
                    }
                }
                Button { showingInsurancePaymentSheet = true } label: {
                    HStack { Image(systemName: "building.columns"); Text("Insurance Payment") }
                        .font(.subheadline).fontWeight(.semibold).foregroundColor(.white)
                        .frame(maxWidth: .infinity).padding()
                        .background(Color("BrandCyan")).cornerRadius(12)
                }
            }
            HStack(spacing: 12) {
                Button { showingDisputeSheet = true } label: {
                    HStack { Image(systemName: "exclamationmark.triangle"); Text("Dispute") }
                        .font(.subheadline).frame(maxWidth: .infinity).padding()
                        .background(Color("BrandNavy")).cornerRadius(10)
                }
                Button {
                    if let phone = providerPhoneNumber {
                        let digits = phone.filter { $0.isNumber }
                        if let url = URL(string: "tel://\(digits)") {
                            UIApplication.shared.open(url)
                        }
                    } else {
                        showingNoPhoneAlert = true
                    }
                } label: {
                    HStack {
                        Image(systemName: "phone")
                        Text(providerPhoneNumber != nil ? "Call Provider" : "No Phone")
                    }
                        .font(.subheadline).frame(maxWidth: .infinity).padding()
                        .background(providerPhoneNumber != nil ? Color("BrandCyan").opacity(0.3) : Color("BrandNavy"))
                        .cornerRadius(10)
                        .foregroundColor(providerPhoneNumber != nil ? Color("BrandCyan") : .secondary)
                }
            }
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter(); f.dateStyle = .medium; return f.string(from: date)
    }
    
    private func statusColor(for status: ClaimStatus) -> Color {
        switch status {
        case .notSubmitted, .submitted, .pending, .inReview: return .orange
        case .approved, .paid: return .green
        case .partiallyApproved: return .yellow
        case .denied: return .red
        case .appealed: return .purple
        case .closed: return .gray
        }
    }
}

// MARK: - Supporting Views

struct BillStatusBadge: View {
    let status: ClaimStatus
    var body: some View {
        Text(status.rawValue).font(.caption).fontWeight(.semibold)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(bgColor.opacity(0.2)).foregroundColor(bgColor).cornerRadius(8)
    }
    private var bgColor: Color {
        switch status {
        case .notSubmitted: return .gray; case .submitted: return .blue; case .pending: return .orange
        case .inReview: return .purple; case .approved: return .green; case .partiallyApproved: return .yellow
        case .denied: return .red; case .appealed: return .orange; case .paid: return .green; case .closed: return .gray
        }
    }
}

struct BillFinancialRow: View {
    let label: String; let amount: Double; let style: RowStyle
    enum RowStyle { case regular, adjustment, payment, total }
    var body: some View {
        HStack {
            Text(label).font(style == .total ? .headline : .subheadline)
                .foregroundColor(style == .total ? .primary : .secondary)
            Spacer()
            Text(amount, format: .currency(code: "USD"))
                .font(style == .total ? .headline : .subheadline)
                .fontWeight(style == .total ? .bold : .regular).foregroundColor(amtColor)
        }
    }
    private var amtColor: Color {
        switch style {
        case .adjustment: return .orange; case .payment: return .green
        case .total: return amount > 0 ? .red : .green; default: return .primary
        }
    }
}

struct BillInfoCell: View {
    let label: String; let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundColor(.secondary)
            Text(value).font(.subheadline)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ProcedureRow: View {
    let item: BillLineItem
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if let code = item.procedureCode {
                    Text(code).font(.system(.caption, design: .monospaced))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color("BrandCyan").opacity(0.1)).foregroundColor(Color("BrandCyan")).cornerRadius(4)
                }
                Spacer()
                Text(item.totalCharge, format: .currency(code: "USD")).font(.subheadline).fontWeight(.medium)
            }
            Text(item.procedureDescription).font(.subheadline).foregroundColor(.secondary).lineLimit(2)
            if let r = item.patientResponsibility, r != item.totalCharge {
                HStack {
                    Text("Your responsibility:").font(.caption).foregroundColor(.secondary)
                    Text(r, format: .currency(code: "USD")).font(.caption).fontWeight(.medium).foregroundColor(.orange)
                }
            }
        }.padding().background(Color("BrandNavy")).cornerRadius(10)
    }
}

struct ProcedureRowSimple: View {
    let code: String
    var body: some View {
        HStack {
            Text(code).font(.system(.body, design: .monospaced))
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Color("BrandCyan").opacity(0.1)).foregroundColor(Color("BrandCyan")).cornerRadius(6)
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
        }.padding().background(Color("BrandNavy")).cornerRadius(10)
    }
}

// MARK: - Procedure Detail View

struct ProcedureDetailView: View {
    let procedureCode: String?
    let lineItem: BillLineItem?
    @EnvironmentObject var appState: AppState
    @State private var codeInfo: MedicalCode?
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                codeHeader
                if let item = lineItem { lineItemDetails(item) }
                if let info = codeInfo { codeInformation(info) }
                if let item = lineItem { financialDetails(item) }
                if let codes = lineItem?.diagnosisCodes, !codes.isEmpty { diagnosisCodesSection(codes) }
                if let mods = lineItem?.modifiers, !mods.isEmpty { modifiersSection(mods) }
                if let notes = lineItem?.notes, !notes.isEmpty { notesSection(notes) }
                if let item = lineItem, item.denialCode != nil || item.denialReason != nil { denialSection(item) }
            }.padding()
        }
        .navigationTitle("Procedure Details")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadCodeInfo() }
    }
    
    private var codeHeader: some View {
        VStack(spacing: 12) {
            if let code = procedureCode {
                Text(code).font(.system(.largeTitle, design: .monospaced)).fontWeight(.bold).foregroundColor(Color("BrandCyan"))
            }
            if let item = lineItem {
                Text(item.procedureDescription).font(.headline).multilineTextAlignment(.center)
            } else if let info = codeInfo {
                Text(info.plainEnglishDescription).font(.headline).multilineTextAlignment(.center)
            }
            if let code = procedureCode {
                Text(codeType(for: code)).font(.caption).padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Color("BrandCyan").opacity(0.1)).foregroundColor(Color("BrandCyan")).cornerRadius(20)
            }
        }.padding().frame(maxWidth: .infinity).background(Color("BrandNavy")).cornerRadius(12)
    }
    
    private func lineItemDetails(_ item: BillLineItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Service Details").font(.headline)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ProcDetailCell(label: "Service Date", value: formatDate(item.serviceDate))
                ProcDetailCell(label: "Quantity", value: "\(item.quantity)")
                ProcDetailCell(label: "Unit Charge", value: formatCurrency(item.unitCharge))
                ProcDetailCell(label: "Total Charge", value: formatCurrency(item.totalCharge))
            }
        }.padding().background(Color("BrandNavy")).cornerRadius(12)
    }
    
    private func codeInformation(_ info: MedicalCode) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Code Information").font(.headline)
            ProcInfoRow(label: "Type", value: info.codeType.displayName)
            ProcInfoRow(label: "Category", value: info.category)
            if let avg = info.priceAverage { ProcInfoRow(label: "Average Cost", value: formatCurrency(avg)) }
            if info.hasValidPricing { ProcInfoRow(label: "Price Range", value: info.formattedPriceRange) }
        }.padding().background(Color("BrandNavy")).cornerRadius(12)
    }
    
    private func financialDetails(_ item: BillLineItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Financial Breakdown").font(.headline)
            VStack(spacing: 10) {
                ProcFinancialRow(label: "Billed Amount", amount: item.totalCharge)
                if let a = item.allowedAmount { ProcFinancialRow(label: "Allowed Amount", amount: a) }
                if let a = item.adjustmentAmount { ProcFinancialRow(label: "Adjustment", amount: -a, isNegative: true) }
                if let p = item.insurancePaid { ProcFinancialRow(label: "Insurance Paid", amount: -p, isNegative: true) }
                Divider()
                if let r = item.patientResponsibility { ProcFinancialRow(label: "Your Responsibility", amount: r, isTotal: true) }
            }
        }.padding().background(Color("BrandNavy")).cornerRadius(12)
    }
    
    private func diagnosisCodesSection(_ codes: [String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Linked Diagnosis Codes").font(.headline)
            ForEach(codes, id: \.self) { code in
                HStack {
                    Text(code).font(.system(.body, design: .monospaced))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Color.purple.opacity(0.1)).foregroundColor(.purple).cornerRadius(6)
                    Spacer()
                    Text("ICD-10").font(.caption).foregroundColor(.secondary)
                }
            }
        }.padding().background(Color("BrandNavy")).cornerRadius(12)
    }
    
    private func modifiersSection(_ modifiers: [String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Modifiers").font(.headline)
            HStack(spacing: 8) {
                ForEach(modifiers, id: \.self) { mod in
                    Text(mod).font(.system(.caption, design: .monospaced))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Color.orange.opacity(0.1)).foregroundColor(.orange).cornerRadius(6)
                }
            }
            Text("Modifiers provide additional information about the procedure.")
                .font(.caption).foregroundColor(.secondary)
        }.padding().background(Color("BrandNavy")).cornerRadius(12)
    }
    
    private func notesSection(_ notes: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Notes").font(.headline)
            Text(notes).font(.subheadline).foregroundColor(.secondary)
        }.padding().frame(maxWidth: .infinity, alignment: .leading)
        .background(Color("BrandNavy")).cornerRadius(12)
    }
    
    private func denialSection(_ item: BillLineItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.red)
                Text("Denial Information").font(.headline)
            }
            if let c = item.denialCode { ProcInfoRow(label: "Denial Code", value: c) }
            if let r = item.denialReason {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Reason").font(.caption).foregroundColor(.secondary)
                    Text(r).font(.subheadline)
                }
            }
        }.padding().background(Color.red.opacity(0.1)).cornerRadius(12)
    }
    
    private func loadCodeInfo() async {
        guard let code = procedureCode else { return }
        if let result = appState.cloudKitService.lookupCode(code) {
            await MainActor.run { codeInfo = result }
        }
    }
    
    private func codeType(for code: String) -> String {
        if code.first?.isLetter == true { return "ICD-10 Diagnosis Code" }
        else if code.count == 5, code.allSatisfy({ $0.isNumber }) { return "CPT Procedure Code" }
        return "Medical Code"
    }
    
    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter(); f.dateStyle = .medium; return f.string(from: date)
    }
    
    private func formatCurrency(_ amount: Double) -> String {
        let f = NumberFormatter(); f.numberStyle = .currency
        return f.string(from: NSNumber(value: amount)) ?? "$\(amount)"
    }
}

struct ProcDetailCell: View {
    let label: String; let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundColor(.secondary)
            Text(value).font(.subheadline).fontWeight(.medium)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ProcInfoRow: View {
    let label: String; let value: String
    var body: some View {
        HStack {
            Text(label).font(.subheadline).foregroundColor(.secondary)
            Spacer()
            Text(value).font(.subheadline)
        }
    }
}

struct ProcFinancialRow: View {
    let label: String; let amount: Double
    var isNegative: Bool = false; var isTotal: Bool = false
    var body: some View {
        HStack {
            Text(label).font(isTotal ? .headline : .subheadline)
                .foregroundColor(isTotal ? .primary : .secondary)
            Spacer()
            Text(amount, format: .currency(code: "USD"))
                .font(isTotal ? .headline : .subheadline)
                .fontWeight(isTotal ? .bold : .regular)
                .foregroundColor(isNegative ? .green : (isTotal ? .orange : .primary))
        }
    }
}

// MARK: - Bill Detail Edit View

struct BillDetailEditView: View {
    let claim: Claim
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var patientDataService: PatientDataService
    
    @State private var providerName = ""
    @State private var claimNumber = ""
    @State private var serviceDate = Date()
    @State private var billedAmount = ""
    @State private var allowedAmount = ""
    @State private var adjustmentAmount = ""
    @State private var paidAmount = ""
    @State private var patientResponsibility = ""
    @State private var deductibleApplied = ""
    @State private var coinsuranceAmount = ""
    @State private var copayAmount = ""
    @State private var status: ClaimStatus = .notSubmitted
    @State private var notes = ""
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Basic Information") {
                    TextField("Provider Name", text: $providerName)
                    TextField("Bill/Claim Number", text: $claimNumber)
                    DatePicker("Service Date", selection: $serviceDate, displayedComponents: .date)
                    Picker("Status", selection: $status) {
                        ForEach(ClaimStatus.allCases, id: \.self) { s in Text(s.rawValue).tag(s) }
                    }
                }
                
                Section("Charges") {
                    AmountField(label: "Total Charges", amount: $billedAmount)
                    AmountField(label: "Allowed Amount", amount: $allowedAmount)
                    AmountField(label: "Adjustments", amount: $adjustmentAmount)
                }
                
                Section("Insurance Payment") {
                    AmountField(label: "Insurance Paid", amount: $paidAmount)
                }
                
                Section("Your Responsibility") {
                    AmountField(label: "Deductible Applied", amount: $deductibleApplied)
                    AmountField(label: "Coinsurance", amount: $coinsuranceAmount)
                    AmountField(label: "Copay", amount: $copayAmount)
                    AmountField(label: "Total Due", amount: $patientResponsibility, isBold: true)
                }
                
                Section("Notes") {
                    TextEditor(text: $notes).frame(minHeight: 80)
                }
            }
            .navigationTitle("Edit Bill")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { saveBill() } }
            }
            .onAppear { loadClaimData() }
        }
    }
    
    private func loadClaimData() {
        providerName = claim.providerName ?? ""
        claimNumber = claim.claimNumber ?? ""
        serviceDate = claim.serviceDate
        billedAmount = String(format: "%.2f", claim.billedAmount)
        allowedAmount = claim.allowedAmount.map { String(format: "%.2f", $0) } ?? ""
        adjustmentAmount = claim.adjustmentAmount.map { String(format: "%.2f", $0) } ?? ""
        paidAmount = claim.paidAmount.map { String(format: "%.2f", $0) } ?? ""
        patientResponsibility = claim.patientResponsibility.map { String(format: "%.2f", $0) } ?? ""
        deductibleApplied = claim.deductibleApplied.map { String(format: "%.2f", $0) } ?? ""
        coinsuranceAmount = claim.coinsuranceAmount.map { String(format: "%.2f", $0) } ?? ""
        copayAmount = claim.copayAmount.map { String(format: "%.2f", $0) } ?? ""
        status = claim.status
        notes = claim.notes ?? ""
    }
    
    private func saveBill() {
        var updated = claim
        updated.providerName = providerName
        updated.claimNumber = claimNumber.isEmpty ? nil : claimNumber
        updated.serviceDate = serviceDate
        updated.billedAmount = Double(billedAmount) ?? claim.billedAmount
        updated.allowedAmount = Double(allowedAmount)
        updated.adjustmentAmount = Double(adjustmentAmount)
        updated.paidAmount = Double(paidAmount)
        updated.patientResponsibility = Double(patientResponsibility)
        updated.deductibleApplied = Double(deductibleApplied)
        updated.coinsuranceAmount = Double(coinsuranceAmount)
        updated.copayAmount = Double(copayAmount)
        updated.status = status
        updated.notes = notes.isEmpty ? nil : notes
        updated.updatedAt = Date()
        patientDataService.saveClaim(updated)
        dismiss()
    }
}

struct AmountField: View {
    let label: String
    @Binding var amount: String
    var isBold: Bool = false
    
    var body: some View {
        HStack {
            Text(label).fontWeight(isBold ? .semibold : .regular)
            Spacer()
            Text("$")
            TextField("0.00", text: $amount)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 100)
                .fontWeight(isBold ? .semibold : .regular)
        }
    }
}

// MARK: - Add Procedure View

struct AddProcedureView: View {
    @Binding var lineItems: [BillLineItem]
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState
    
    @State private var procedureCode = ""
    @State private var description = ""
    @State private var serviceDate = Date()
    @State private var quantity = "1"
    @State private var unitCharge = ""
    @State private var diagnosisCodes = ""
    @State private var modifiers = ""
    @State private var notes = ""
    
    // Code lookup
    @State private var showingCodeLookup = false
    @State private var matchedCode: MedicalCode?
    @State private var showingScanner = false
    @State private var showingBillScanner = false
    
    var body: some View {
        NavigationStack {
            Form {
                // Quick Actions
                Section {
                    VStack(spacing: 12) {
                        HStack(spacing: 12) {
                            Button {
                                showingScanner = true
                            } label: {
                                HStack {
                                    Image(systemName: "doc.text.viewfinder").font(.title3).frame(width: 28)
                                    Text("Scan Code").fontWeight(.semibold)
                                    Spacer()
                                    Image(systemName: "chevron.right").foregroundColor(.white)
                                }
                                .padding(.horizontal, 12).padding(.vertical, 10)
                                .frame(maxWidth: .infinity)
                                .background(Color.accentColor)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                            }
                            .buttonStyle(.plain)
                            
                            Button {
                                showingCodeLookup = true
                            } label: {
                                VStack(spacing: 6) {
                                    Image(systemName: "magnifyingglass")
                                        .font(.title2)
                                    Text("Lookup")
                                        .font(.caption)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.green.opacity(0.1))
                                .foregroundColor(.green)
                                .cornerRadius(10)
                            }
                            .buttonStyle(.plain)
                        }
                        
                        // Full Bill Scanner
                        Button {
                            showingBillScanner = true
                        } label: {
                            HStack {
                                Image(systemName: "doc.text.image").font(.title3).frame(width: 30)
                                Text("Scan Full Bill with OCR").fontWeight(.semibold)
                                Spacer()
                                Image(systemName: "chevron.right").foregroundColor(.white)
                            }
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.accentColor)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                Section("Procedure Information") {
                    HStack {
                        TextField("CPT/HCPCS Code", text: $procedureCode)
                            .textInputAutocapitalization(.characters)
                            .onChange(of: procedureCode) { _, newValue in
                                lookupCode(newValue)
                            }
                        
                        if matchedCode != nil {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        }
                    }
                    
                    TextField("Description", text: $description)
                    
                    // Show matched code info
                    if let code = matchedCode {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(code.codeType.displayName)
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.accentColor.opacity(0.1))
                                    .foregroundColor(.accentColor)
                                    .cornerRadius(4)
                                
                                Spacer()
                                
                                Button("Use This") {
                                    description = code.shortDescription
                                    if let avg = code.priceAverage {
                                        unitCharge = String(format: "%.2f", avg)
                                    }
                                }
                                .font(.caption)
                                .buttonStyle(.bordered)
                            }
                            
                            Text(code.plainEnglishDescription)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            if code.hasValidPricing {
                                HStack {
                                    Image(systemName: "dollarsign.circle")
                                        .foregroundColor(.secondary)
                                    Text("Typical cost: \(code.formattedPriceRange)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    
                    DatePicker("Service Date", selection: $serviceDate, displayedComponents: .date)
                }
                
                Section("Charges") {
                    HStack {
                        Text("Quantity")
                        Spacer()
                        TextField("1", text: $quantity)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                    }
                    
                    HStack {
                        Text("Unit Charge")
                        Spacer()
                        Text("$")
                        TextField("0.00", text: $unitCharge)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                    }
                    
                    if let total = calculateTotal() {
                        HStack {
                            Text("Total")
                                .fontWeight(.semibold)
                            Spacer()
                            Text(total, format: .currency(code: "USD"))
                                .fontWeight(.semibold)
                        }
                        
                        // Cost comparison
                        if let code = matchedCode, code.hasValidPricing {
                            let status = getCostStatus(total: total, code: code)
                            HStack {
                                Image(systemName: status.icon)
                                    .foregroundColor(status.color)
                                Text(status.message)
                                    .font(.caption)
                                    .foregroundColor(status.color)
                            }
                        }
                    }
                }
                
                Section("Coding (Optional)") {
                    TextField("Diagnosis Codes (comma separated)", text: $diagnosisCodes)
                        .textInputAutocapitalization(.characters)
                    TextField("Modifiers (comma separated)", text: $modifiers)
                        .textInputAutocapitalization(.characters)
                }
                
                Section("Notes") {
                    TextField("Optional notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Add Procedure")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { addProcedure() }
                        .disabled(!canAdd)
                }
            }
            .sheet(isPresented: $showingCodeLookup) {
                CodeLookupSheet(
                    selectedCode: $matchedCode,
                    procedureCode: $procedureCode,
                    description: $description,
                    unitCharge: $unitCharge
                )
                .environmentObject(appState)
            }
            .sheet(isPresented: $showingScanner) {
                ProcedureScannerSheet(
                    procedureCode: $procedureCode,
                    description: $description,
                    unitCharge: $unitCharge,
                    matchedCode: $matchedCode
                )
                .environmentObject(appState)
            }
            .fullScreenCover(isPresented: $showingBillScanner) {
                BillOCRScanner(lineItems: $lineItems) { extractedProc in
                    // If a single procedure was selected, fill in the form
                    procedureCode = extractedProc.code
                    description = extractedProc.description
                    if extractedProc.totalCost > 0 {
                        unitCharge = String(format: "%.2f", extractedProc.totalCost)
                    } else if let avg = extractedProc.normalCostAverage {
                        unitCharge = String(format: "%.2f", avg)
                    }
                    matchedCode = extractedProc.matchedCode
                }
                .environmentObject(appState)
            }
        }
    }
    
    private var canAdd: Bool {
        !description.isEmpty || !procedureCode.isEmpty
    }
    
    private func calculateTotal() -> Double? {
        guard let unit = Double(unitCharge), let qty = Int(quantity) else { return nil }
        return unit * Double(qty)
    }
    
    private func lookupCode(_ code: String) {
        guard code.count >= 5 else {
            matchedCode = nil
            return
        }
        
        matchedCode = appState.cloudKitService.lookupCode(code)
    }
    
    private func getCostStatus(total: Double, code: MedicalCode) -> (icon: String, color: Color, message: String) {
        guard let low = code.priceLow, let high = code.priceHigh else {
            return ("questionmark.circle", .gray, "No cost data available")
        }
        
        if total < low {
            return ("arrow.down.circle.fill", .green, "Below typical range (\(code.formattedPriceRange))")
        } else if total > high {
            return ("exclamationmark.triangle.fill", .orange, "Above typical range (\(code.formattedPriceRange))")
        } else {
            return ("checkmark.circle.fill", .blue, "Within typical range")
        }
    }
    
    private func addProcedure() {
        let unit = Double(unitCharge) ?? 0
        let qty = Int(quantity) ?? 1
        
        let diagCodes = diagnosisCodes.isEmpty ? nil : diagnosisCodes.components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let mods = modifiers.isEmpty ? nil : modifiers.components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        
        // Use matched code description if no description entered
        var finalDescription = description
        if finalDescription.isEmpty, let code = matchedCode {
            finalDescription = code.shortDescription
        }
        if finalDescription.isEmpty {
            finalDescription = "Procedure \(procedureCode)"
        }
        
        let item = BillLineItem(
            procedureCode: procedureCode.isEmpty ? nil : procedureCode,
            procedureDescription: finalDescription,
            diagnosisCodes: diagCodes,
            modifiers: mods,
            serviceDate: serviceDate,
            quantity: qty,
            unitCharge: unit,
            notes: notes.isEmpty ? nil : notes
        )
        lineItems.append(item)
        dismiss()
    }
}

// MARK: - Code Lookup Sheet

struct CodeLookupSheet: View {
    @Binding var selectedCode: MedicalCode?
    @Binding var procedureCode: String
    @Binding var description: String
    @Binding var unitCharge: String
    
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState
    
    @State private var searchText = ""
    @State private var searchResults: [MedicalCode] = []
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search codes or descriptions", text: $searchText)
                        .textInputAutocapitalization(.never)
                        .onChange(of: searchText) { _, newValue in
                            search(newValue)
                        }
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                            searchResults = []
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding()
                .background(Color("BrandNavy"))
                
                // Results
                if searchResults.isEmpty {
                    VStack(spacing: 16) {
                        Spacer()
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 50))
                            .foregroundColor(.secondary)
                        Text("Search for a procedure code")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text("Enter a CPT code or description")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                } else {
                    List(searchResults) { code in
                        Button {
                            selectCode(code)
                        } label: {
                            CodeSearchResultRow(code: code)
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Lookup Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
    
    private func search(_ query: String) {
        guard query.count >= 2 else {
            searchResults = []
            return
        }
        searchResults = appState.cloudKitService.searchCodesOffline(query: query)
    }
    
    private func selectCode(_ code: MedicalCode) {
        selectedCode = code
        procedureCode = code.code
        description = code.shortDescription
        if let avg = code.priceAverage {
            unitCharge = String(format: "%.2f", avg)
        }
        dismiss()
    }
}

// MARK: - Code Search Result Row

struct CodeSearchResultRow: View {
    let code: MedicalCode
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(code.code)
                    .font(.system(.headline, design: .monospaced))
                    .foregroundColor(.accentColor)
                
                Text(code.codeType.displayName)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.1))
                    .foregroundColor(.accentColor)
                    .cornerRadius(4)
                
                Spacer()
                
                if code.hasValidPricing {
                    Text(code.formattedPriceRange)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Text(code.shortDescription)
                .font(.subheadline)
                .foregroundColor(.primary)
            
            Text(code.plainEnglishDescription)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Procedure Scanner Sheet

struct ProcedureScannerSheet: View {
    @Binding var procedureCode: String
    @Binding var description: String
    @Binding var unitCharge: String
    @Binding var matchedCode: MedicalCode?
    
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState
    
    @State private var selectedImage: UIImage?
    @State private var showingPhotoPicker = false
    @State private var showingFilePicker = false
    @State private var showingCamera = false
    @State private var isProcessing = false
    @State private var extractedText = ""
    @State private var extractedCodes: [ExtractedProcedureLine] = []
    @State private var showingResults = false
    @State private var showingRawText = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if showingResults {
                    resultsView
                } else if isProcessing {
                    processingView
                } else {
                    sourceSelectionView
                }
            }
            .navigationTitle("Scan Procedure")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if showingResults {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(showingRawText ? "Codes" : "Raw Text") {
                            showingRawText.toggle()
                        }
                    }
                }
            }
            .fullScreenCover(isPresented: $showingCamera) {
                SmartDocumentScanner(capturedImage: $selectedImage)
            }
            .sheet(isPresented: $showingPhotoPicker) {
                PhotoPicker(image: $selectedImage)
            }
            .sheet(isPresented: $showingFilePicker) {
                FilePicker(image: $selectedImage)
            }
            .onChange(of: selectedImage) { _, newImage in
                if newImage != nil {
                    processImage()
                }
            }
        }
    }
    
    private var sourceSelectionView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "doc.text.viewfinder")
                .font(.system(size: 60))
                .foregroundStyle(
                    LinearGradient(colors: [.accentColor, .accentColor.opacity(0.6)],
                                   startPoint: .top, endPoint: .bottom)
                )
            
            VStack(spacing: 8) {
                Text("Scan Procedure Codes")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Extract procedure codes and descriptions\nfrom medical bills and documents")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            VStack(spacing: 12) {
                Button {
                    showingCamera = true
                } label: {
                    HStack {
                        Image(systemName: "camera.fill").font(.title3).frame(width: 30)
                        Text("Take Photo").fontWeight(.semibold)
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                
                Button {
                    showingPhotoPicker = true
                } label: {
                    HStack {
                        Image(systemName: "photo.on.rectangle")
                            .font(.title3)
                            .foregroundColor(.green)
                        VStack(alignment: .leading) {
                            Text("Photo Library")
                                .fontWeight(.semibold)
                            Text("Select from saved photos")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color("BrandNavy"))
                    .foregroundColor(.primary)
                    .cornerRadius(12)
                }
                
                Button {
                    showingFilePicker = true
                } label: {
                    HStack {
                        Image(systemName: "folder.fill")
                            .font(.title3)
                            .foregroundColor(.orange)
                        VStack(alignment: .leading) {
                            Text("Files")
                                .fontWeight(.semibold)
                            Text("Import PDF or image files")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color("BrandNavy"))
                    .foregroundColor(.primary)
                    .cornerRadius(12)
                }
            }
            .padding(.horizontal)
            
            Spacer()
            
            // Tips
            VStack(alignment: .leading, spacing: 8) {
                Text("Supported formats:")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                HStack(spacing: 16) {
                    Label("CPT Codes", systemImage: "number")
                    Label("HCPCS", systemImage: "tag")
                    Label("ICD-10", systemImage: "cross.case")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color("BrandNavy"))
            .cornerRadius(12)
            .padding()
        }
    }
    
    private var processingView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            if let image = selectedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 200)
                    .cornerRadius(12)
                    .shadow(radius: 5)
            }
            
            LoadingShieldView(size: 80)
            
            VStack(spacing: 8) {
                Text("Scanning document...")
                    .font(.headline)
                Text("Extracting procedure codes and descriptions")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding()
    }
    
    private var resultsView: some View {
        VStack(spacing: 0) {
            if showingRawText {
                // Show raw extracted text
                VStack(spacing: 12) {
                    HStack {
                        Text("Extracted Text")
                            .font(.headline)
                        Spacer()
                        Button("Copy") {
                            UIPasteboard.general.string = extractedText
                        }
                        .font(.caption)
                    }
                    .padding(.horizontal)
                    .padding(.top)
                    
                    ScrollView {
                        Text(extractedText.isEmpty ? "No text extracted" : extractedText)
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                    .background(Color("BrandNavy"))
                    .cornerRadius(8)
                    .padding(.horizontal)
                    
                    // Manual entry section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Manual Entry")
                            .font(.headline)
                        
                        Text("Didn't find what you need? Enter manually:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Button {
                            // Use first line as description if no codes found
                            if !extractedText.isEmpty {
                                let firstLine = extractedText.components(separatedBy: .newlines).first ?? ""
                                description = firstLine.trimmingCharacters(in: .whitespaces)
                            }
                            dismiss()
                        } label: {
                            Text("Use First Line as Description")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.accentColor)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                    }
                    .padding()
                }
            } else if extractedCodes.isEmpty {
                // No codes found view
                VStack(spacing: 20) {
                    Spacer()
                    
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 50))
                        .foregroundColor(.secondary)
                    
                    Text("No procedure codes found")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    Text("Try viewing the raw text or scan another document")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    
                    HStack(spacing: 12) {
                        Button("View Raw Text") {
                            showingRawText = true
                        }
                        .buttonStyle(.bordered)
                        
                        Button("Scan Again") {
                            selectedImage = nil
                            showingResults = false
                            extractedText = ""
                            extractedCodes = []
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    
                    Spacer()
                }
                .padding()
            } else {
                // Show extracted codes
                List {
                    Section {
                        ForEach(extractedCodes) { proc in
                            Button {
                                selectProcedure(proc)
                            } label: {
                                ExtractedProcedureRow(procedure: proc)
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Text("Found \(extractedCodes.count) procedure(s)")
                    } footer: {
                        Text("Tap a procedure to use it")
                    }
                    
                    Section("Other Options") {
                        Button {
                            showingRawText = true
                        } label: {
                            Label("View Raw Extracted Text", systemImage: "doc.plaintext")
                        }
                        
                        Button {
                            selectedImage = nil
                            showingResults = false
                            extractedText = ""
                            extractedCodes = []
                        } label: {
                            Label("Scan Another Document", systemImage: "arrow.counterclockwise")
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
    }
    
    private func processImage() {
        guard let image = selectedImage else { return }
        isProcessing = true
        
        Task {
            do {
                let text = try await extractText(from: image)
                let codes = parseProcedureCodes(from: text)
                
                await MainActor.run {
                    extractedText = text
                    extractedCodes = codes
                    isProcessing = false
                    showingResults = true
                }
            } catch {
                await MainActor.run {
                    extractedText = "Error extracting text: \(error.localizedDescription)"
                    isProcessing = false
                    showingResults = true
                }
            }
        }
    }
    
    private func extractText(from image: UIImage) async throws -> String {
        guard let cgImage = image.cgImage else {
            throw NSError(domain: "Scanner", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid image"])
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: "")
                    return
                }
                
                let text = observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
                continuation.resume(returning: text)
            }
            
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    private func parseProcedureCodes(from text: String) -> [ExtractedProcedureLine] {
        var procedures: [ExtractedProcedureLine] = []
        let lines = text.components(separatedBy: .newlines)
        
        // Patterns for different code types
        let cptPattern = #"\b\d{5}\b"#  // 5-digit CPT codes
        let hcpcsPattern = #"\b[A-Z]\d{4}\b"#  // HCPCS codes like A1234
        let icd10Pattern = #"\b[A-Z]\d{2}\.?\d{0,4}\b"#  // ICD-10 codes like A00.0
        let amountPattern = #"\$?\s*\d{1,3}(?:,\d{3})*(?:\.\d{2})?"#
        
        for line in lines {
            var procedure = ExtractedProcedureLine()
            var foundCode = false
            
            // Try CPT first (most common)
            if let codeMatch = line.range(of: cptPattern, options: .regularExpression) {
                procedure.code = String(line[codeMatch])
                foundCode = true
            }
            // Try HCPCS
            else if let codeMatch = line.range(of: hcpcsPattern, options: .regularExpression) {
                procedure.code = String(line[codeMatch])
                foundCode = true
            }
            // Try ICD-10
            else if let codeMatch = line.range(of: icd10Pattern, options: .regularExpression) {
                let potentialCode = String(line[codeMatch])
                // Filter out false positives (single letters followed by numbers that aren't codes)
                if potentialCode.count >= 3 {
                    procedure.code = potentialCode
                    foundCode = true
                }
            }
            
            if foundCode {
                // Extract amounts
                if let amountRegex = try? Regex(amountPattern) {
                    let amounts = line.matches(of: amountRegex).compactMap { match -> Double? in
                        let str = String(line[match.range])
                            .replacingOccurrences(of: "$", with: "")
                            .replacingOccurrences(of: ",", with: "")
                            .trimmingCharacters(in: .whitespaces)
                        return Double(str)
                    }
                    
                    if let lastAmount = amounts.last {
                        procedure.totalCost = lastAmount
                    }
                }
                
                // Get description - text after removing code and amounts
                var desc = line
                desc = desc.replacingOccurrences(of: procedure.code, with: "")
                if let amountRegex = try? Regex(amountPattern) {
                    for match in line.matches(of: amountRegex) {
                        desc = desc.replacingOccurrences(of: String(line[match.range]), with: "")
                    }
                }
                procedure.description = desc
                    .trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "|-:•·"))
                    .trimmingCharacters(in: .whitespaces)
                
                // Match with database
                if let match = appState.cloudKitService.lookupCode(procedure.code) {
                    procedure.matchedCode = match
                    procedure.normalCostLow = match.priceLow
                    procedure.normalCostHigh = match.priceHigh
                    procedure.normalCostAverage = match.priceAverage
                    
                    // Use database description if scanned one is poor
                    if procedure.description.count < 5 {
                        procedure.description = match.shortDescription
                    }
                }
                
                if !procedure.code.isEmpty {
                    procedures.append(procedure)
                }
            }
        }
        
        // Remove duplicates
        var seen = Set<String>()
        procedures = procedures.filter { proc in
            if seen.contains(proc.code) {
                return false
            }
            seen.insert(proc.code)
            return true
        }
        
        return procedures
    }
    
    private func selectProcedure(_ proc: ExtractedProcedureLine) {
        procedureCode = proc.code
        description = proc.description
        if proc.totalCost > 0 {
            unitCharge = String(format: "%.2f", proc.totalCost)
        } else if let avg = proc.normalCostAverage {
            unitCharge = String(format: "%.2f", avg)
        }
        matchedCode = proc.matchedCode
        dismiss()
    }
}

// MARK: - Extracted Procedure Row

struct ExtractedProcedureRow: View {
    let procedure: ExtractedProcedureLine
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(procedure.code)
                    .font(.system(.headline, design: .monospaced))
                    .foregroundColor(.accentColor)
                
                if procedure.matchedCode != nil {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                }
                
                Spacer()
                
                if procedure.totalCost > 0 {
                    Text(procedure.totalCost, format: .currency(code: "USD"))
                        .fontWeight(.medium)
                }
            }
            
            Text(procedure.description)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(2)
            
            if procedure.hasCostComparison {
                HStack {
                    Text("Normal: \(procedure.normalCostLow ?? 0, format: .currency(code: "USD")) – \(procedure.normalCostHigh ?? 0, format: .currency(code: "USD"))")
                        .font(.caption)
                        .foregroundColor(procedure.costStatus.color)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Bill OCR Scanner (Full Bill Scanning)

struct BillOCRScanner: View {
    @Binding var lineItems: [BillLineItem]
    let onSelectSingle: (ExtractedProcedureLine) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState
    
    @State private var selectedImage: UIImage?
    @State private var showingPhotoPicker = false
    @State private var showingFilePicker = false
    @State private var showingCamera = false
    @State private var isProcessing = false
    @State private var extractedText = ""
    @State private var extractedCodes: [ExtractedProcedureLine] = []
    @State private var selectedCodes: Set<String> = []
    @State private var showingResults = false
    
    // Region selection state
    @State private var showingRegionSelector = false
    @State private var codesBox = SelectionBox(
        position: CGPoint(x: 0.5, y: 0.5),
        size: CGSize(width: 0.9, height: 0.6)
    )
    @State private var useFullImage = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if showingResults {
                    resultsView
                } else if isProcessing {
                    processingView
                } else if showingRegionSelector {
                    regionSelectorView
                } else {
                    sourceSelectionView
                }
            }
            .navigationTitle("Scan Medical Bill")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundColor(.secondary)
                    }
                }
                if showingResults && !extractedCodes.isEmpty {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Add Selected") {
                            addSelectedProcedures()
                        }
                        .disabled(selectedCodes.isEmpty)
                    }
                }
            }
            .fullScreenCover(isPresented: $showingCamera) {
                SmartDocumentScanner(capturedImage: $selectedImage)
            }
            .sheet(isPresented: $showingPhotoPicker) {
                PhotoPicker(image: $selectedImage)
            }
            .sheet(isPresented: $showingFilePicker) {
                FilePicker(image: $selectedImage)
            }
            .onChange(of: selectedImage) { _, newImage in
                if newImage != nil {
                    // Show region selector instead of processing immediately
                    showingRegionSelector = true
                }
            }
        }
    }
    
    // MARK: - Region Selector View
    
    private var regionSelectorView: some View {
        VStack(spacing: 0) {
            // Instructions bar
            HStack(spacing: 8) {
                Image(systemName: "hand.draw")
                    .foregroundColor(.orange)
                Text("Position the box over the procedure codes table")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(Color("BrandNavy"))
            
            // Image with adjustable rectangle
            GeometryReader { geometry in
                if let image = selectedImage {
                    let imageFrame = calculateImageFrame(image: image, in: geometry.size)
                    
                    ZStack {
                        // Background image
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(width: imageFrame.width, height: imageFrame.height)
                            .position(x: imageFrame.midX, y: imageFrame.midY)
                        
                        // Dimmed overlay outside the box
                        CodesRegionDimOverlay(
                            box: codesBox,
                            containerSize: CGSize(width: imageFrame.width, height: imageFrame.height),
                            offset: CGPoint(x: imageFrame.origin.x, y: imageFrame.origin.y)
                        )
                        
                        // Draggable selection box
                        DraggableBox(
                            box: $codesBox,
                            containerSize: CGSize(width: imageFrame.width, height: imageFrame.height),
                            offset: CGPoint(x: imageFrame.origin.x, y: imageFrame.origin.y),
                            color: .orange,
                            label: "Codes Area",
                            isActive: true
                        )
                    }
                }
            }
            
            // Bottom controls
            VStack(spacing: 12) {
                // Size presets
                Text("Box Size Presets")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 12) {
                    Button("Narrow") {
                        withAnimation {
                            codesBox.size = CGSize(width: 0.9, height: 0.25)
                            codesBox.position = CGPoint(x: 0.5, y: 0.5)
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)
                    
                    Button("Medium") {
                        withAnimation {
                            codesBox.size = CGSize(width: 0.9, height: 0.45)
                            codesBox.position = CGPoint(x: 0.5, y: 0.5)
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)
                    
                    Button("Large") {
                        withAnimation {
                            codesBox.size = CGSize(width: 0.95, height: 0.7)
                            codesBox.position = CGPoint(x: 0.5, y: 0.5)
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)
                    
                    Button("Full") {
                        withAnimation {
                            codesBox.size = CGSize(width: 1.0, height: 1.0)
                            codesBox.position = CGPoint(x: 0.5, y: 0.5)
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)
                }
                
                HStack(spacing: 12) {
                    Button {
                        showingRegionSelector = false
                        selectedImage = nil
                    } label: {
                        HStack {
                            Image(systemName: "arrow.counterclockwise")
                            Text("Retake")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color("BrandNavy"))
                        .foregroundColor(.primary)
                        .cornerRadius(10)
                    }
                    
                    Button {
                        processImageRegion()
                    } label: {
                        HStack {
                            Image(systemName: "doc.text.viewfinder")
                            Text("Extract Codes")
                        }
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                }
            }
            .padding()
            .background(Color("BrandDeepNavy"))
        }
    }
    
    private func calculateImageFrame(image: UIImage, in containerSize: CGSize) -> CGRect {
        let imageAspect = image.size.width / image.size.height
        let containerAspect = containerSize.width / containerSize.height
        
        var size: CGSize
        if imageAspect > containerAspect {
            size = CGSize(width: containerSize.width, height: containerSize.width / imageAspect)
        } else {
            size = CGSize(width: containerSize.height * imageAspect, height: containerSize.height)
        }
        
        let origin = CGPoint(
            x: (containerSize.width - size.width) / 2,
            y: (containerSize.height - size.height) / 2
        )
        
        return CGRect(origin: origin, size: size)
    }
    
    private func cropImageToBox(_ image: UIImage, box: SelectionBox) -> UIImage? {
        let imgW = image.size.width
        let imgH = image.size.height
        
        let x = max(0, (box.position.x - box.size.width / 2)) * imgW
        let y = max(0, (box.position.y - box.size.height / 2)) * imgH
        let w = min(box.size.width * imgW, imgW - x)
        let h = min(box.size.height * imgH, imgH - y)
        
        let cropRect = CGRect(x: x, y: y, width: w, height: h)
        
        guard let cgImage = image.cgImage?.cropping(to: cropRect) else { return nil }
        return UIImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)
    }
    
    private func processImageRegion() {
        guard let image = selectedImage else { return }
        showingRegionSelector = false
        isProcessing = true
        
        // Crop to box region
        let croppedImage = cropImageToBox(image, box: codesBox) ?? image
        
        Task {
            do {
                let text = try await extractText(from: croppedImage)
                let codes = parseProcedureCodes(from: text)
                
                await MainActor.run {
                    extractedText = text
                    extractedCodes = codes
                    selectedCodes = Set(codes.map { $0.id.uuidString })
                    isProcessing = false
                    showingResults = true
                }
            } catch {
                await MainActor.run {
                    extractedText = "Error: \(error.localizedDescription)"
                    isProcessing = false
                    showingResults = true
                }
            }
        }
    }
    
    private var sourceSelectionView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            // Icon
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.1))
                    .frame(width: 120, height: 120)
                
                Image(systemName: "doc.text.image")
                    .font(.system(size: 50))
                    .foregroundColor(.orange)
            }
            
            VStack(spacing: 8) {
                Text("Scan Medical Bill")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Use OCR to extract all procedure codes\nand descriptions from your bill")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            VStack(spacing: 12) {
                Button {
                    showingCamera = true
                } label: {
                    HStack {
                        Image(systemName: "camera.fill").font(.title3).frame(width: 30)
                        Text("Take Photo").fontWeight(.semibold)
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                
                Button {
                    showingPhotoPicker = true
                } label: {
                    HStack {
                        Image(systemName: "photo.on.rectangle")
                            .font(.title3)
                            .frame(width: 30)
                        Text("Photo Library")
                            .fontWeight(.semibold)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color("BrandNavy"))
                    .foregroundColor(.primary)
                    .cornerRadius(12)
                }
                
                Button {
                    showingFilePicker = true
                } label: {
                    HStack {
                        Image(systemName: "folder.fill")
                            .font(.title3)
                            .frame(width: 30)
                        Text("Import PDF or Image")
                            .fontWeight(.semibold)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color("BrandNavy"))
                    .foregroundColor(.primary)
                    .cornerRadius(12)
                }
            }
            .padding(.horizontal)
            
            Spacer()
            
            // Info
            HStack(spacing: 12) {
                Image(systemName: "info.circle")
                    .foregroundColor(.orange)
                Text("You can select multiple procedures to add at once")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
        }
    }
    
    private var processingView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            if let image = selectedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 200)
                    .cornerRadius(12)
                    .shadow(radius: 5)
            }
            
            Loading3DRingView(size: 60, color: .orange)
            
            VStack(spacing: 8) {
                Text("Analyzing Bill...")
                    .font(.headline)
                Text("Extracting procedure codes and costs")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding()
    }
    
    private var resultsView: some View {
        VStack(spacing: 0) {
            if extractedCodes.isEmpty {
                // No codes found
                VStack(spacing: 20) {
                    Spacer()
                    
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 50))
                        .foregroundColor(.secondary)
                    
                    Text("No procedure codes found")
                        .font(.headline)
                    
                    Text("Try a clearer image or different document")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    if !extractedText.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Extracted text preview:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Text(String(extractedText.prefix(200)) + (extractedText.count > 200 ? "..." : ""))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .padding()
                                .background(Color("BrandNavy"))
                                .cornerRadius(8)
                        }
                        .padding()
                    }
                    
                    HStack(spacing: 12) {
                        Button("Adjust Region") {
                            rescanWithRegion()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.blue)
                        
                        Button("New Image") {
                            resetScanner()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                    }
                    
                    Spacer()
                }
                .padding()
            } else {
                // Show extracted codes with selection
                VStack(spacing: 0) {
                    // Summary bar
                    HStack {
                        Text("\(extractedCodes.count) procedures found")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Button(selectedCodes.count == extractedCodes.count ? "Deselect All" : "Select All") {
                            if selectedCodes.count == extractedCodes.count {
                                selectedCodes.removeAll()
                            } else {
                                selectedCodes = Set(extractedCodes.map { $0.id.uuidString })
                            }
                        }
                        .font(.caption)
                    }
                    .padding()
                    .background(Color("BrandNavy"))
                    
                    List {
                        ForEach(extractedCodes) { proc in
                            BillProcedureSelectRow(
                                procedure: proc,
                                isSelected: selectedCodes.contains(proc.id.uuidString),
                                onToggle: {
                                    if selectedCodes.contains(proc.id.uuidString) {
                                        selectedCodes.remove(proc.id.uuidString)
                                    } else {
                                        selectedCodes.insert(proc.id.uuidString)
                                    }
                                },
                                onUseSingle: {
                                    onSelectSingle(proc)
                                    dismiss()
                                }
                            )
                        }
                        
                        Section {
                            Button {
                                rescanWithRegion()
                            } label: {
                                Label("Adjust Region & Rescan", systemImage: "crop")
                            }
                            Button {
                                resetScanner()
                            } label: {
                                Label("Scan New Image", systemImage: "arrow.counterclockwise")
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
        }
    }
    
    private func resetScanner() {
        selectedImage = nil
        showingResults = false
        showingRegionSelector = false
        extractedText = ""
        extractedCodes = []
        selectedCodes = []
        // Reset box to default
        codesBox = SelectionBox(
            position: CGPoint(x: 0.5, y: 0.5),
            size: CGSize(width: 0.9, height: 0.6)
        )
    }
    
    private func rescanWithRegion() {
        // Go back to region selector with the same image
        showingResults = false
        showingRegionSelector = true
        extractedText = ""
        extractedCodes = []
        selectedCodes = []
    }
    
    private func extractText(from image: UIImage) async throws -> String {
        guard let cgImage = image.cgImage else {
            throw NSError(domain: "Scanner", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid image"])
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: "")
                    return
                }
                
                let text = observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
                continuation.resume(returning: text)
            }
            
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    private func parseProcedureCodes(from text: String) -> [ExtractedProcedureLine] {
        var procedures: [ExtractedProcedureLine] = []
        let lines = text.components(separatedBy: .newlines)
        
        let cptPattern = #"\b\d{5}\b"#
        let hcpcsPattern = #"\b[A-Z]\d{4}\b"#
        let icd10Pattern = #"\b[A-Z]\d{2}\.?\d{0,4}\b"#
        let amountPattern = #"\$?\s*\d{1,3}(?:,\d{3})*(?:\.\d{2})?"#
        
        for line in lines {
            var procedure = ExtractedProcedureLine()
            var foundCode = false
            
            if let codeMatch = line.range(of: cptPattern, options: .regularExpression) {
                procedure.code = String(line[codeMatch])
                foundCode = true
            } else if let codeMatch = line.range(of: hcpcsPattern, options: .regularExpression) {
                procedure.code = String(line[codeMatch])
                foundCode = true
            } else if let codeMatch = line.range(of: icd10Pattern, options: .regularExpression) {
                let potentialCode = String(line[codeMatch])
                if potentialCode.count >= 3 {
                    procedure.code = potentialCode
                    foundCode = true
                }
            }
            
            if foundCode {
                if let amountRegex = try? Regex(amountPattern) {
                    let amounts = line.matches(of: amountRegex).compactMap { match -> Double? in
                        let str = String(line[match.range])
                            .replacingOccurrences(of: "$", with: "")
                            .replacingOccurrences(of: ",", with: "")
                            .trimmingCharacters(in: .whitespaces)
                        return Double(str)
                    }
                    
                    if let lastAmount = amounts.last {
                        procedure.totalCost = lastAmount
                    }
                }
                
                var desc = line
                desc = desc.replacingOccurrences(of: procedure.code, with: "")
                if let amountRegex = try? Regex(amountPattern) {
                    for match in line.matches(of: amountRegex) {
                        desc = desc.replacingOccurrences(of: String(line[match.range]), with: "")
                    }
                }
                procedure.description = desc
                    .trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "|-:•·"))
                    .trimmingCharacters(in: .whitespaces)
                
                if let match = appState.cloudKitService.lookupCode(procedure.code) {
                    procedure.matchedCode = match
                    procedure.normalCostLow = match.priceLow
                    procedure.normalCostHigh = match.priceHigh
                    procedure.normalCostAverage = match.priceAverage
                    
                    if procedure.description.count < 5 {
                        procedure.description = match.shortDescription
                    }
                }
                
                if !procedure.code.isEmpty {
                    procedures.append(procedure)
                }
            }
        }
        
        // Remove duplicates
        var seen = Set<String>()
        procedures = procedures.filter { proc in
            if seen.contains(proc.code) { return false }
            seen.insert(proc.code)
            return true
        }
        
        return procedures
    }
    
    private func addSelectedProcedures() {
        for proc in extractedCodes where selectedCodes.contains(proc.id.uuidString) {
            let item = BillLineItem(
                procedureCode: proc.code,
                procedureDescription: proc.description,
                serviceDate: proc.serviceDate,
                quantity: proc.quantity,
                unitCharge: proc.totalCost > 0 ? proc.totalCost : (proc.normalCostAverage ?? 0)
            )
            lineItems.append(item)
        }
        dismiss()
    }
}

// MARK: - Bill Procedure Select Row

struct BillProcedureSelectRow: View {
    let procedure: ExtractedProcedureLine
    let isSelected: Bool
    let onToggle: () -> Void
    let onUseSingle: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Selection checkbox
            Button {
                onToggle()
            } label: {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundColor(isSelected ? .orange : .secondary)
            }
            .buttonStyle(.plain)
            
            // Procedure info
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(procedure.code)
                        .font(.system(.headline, design: .monospaced))
                        .foregroundColor(.accentColor)
                    
                    if procedure.matchedCode != nil {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                    }
                    
                    Spacer()
                    
                    if procedure.totalCost > 0 {
                        Text(procedure.totalCost, format: .currency(code: "USD"))
                            .fontWeight(.semibold)
                    }
                }
                
                Text(procedure.description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                
                if procedure.hasCostComparison {
                    HStack {
                        Image(systemName: "chart.bar")
                            .font(.caption2)
                        Text("Normal: \(procedure.normalCostLow ?? 0, format: .currency(code: "USD")) – \(procedure.normalCostHigh ?? 0, format: .currency(code: "USD"))")
                            .font(.caption)
                    }
                    .foregroundColor(procedure.costStatus.color)
                }
            }
            
            // Use single button
            Button {
                onUseSingle()
            } label: {
                Text("Use")
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.accentColor.opacity(0.1))
                    .foregroundColor(.accentColor)
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Codes Region Dim Overlay

struct CodesRegionDimOverlay: View {
    let box: SelectionBox
    let containerSize: CGSize
    let offset: CGPoint
    
    var body: some View {
        Canvas { context, size in
            // Fill entire area with dim
            let fullRect = CGRect(origin: .zero, size: size)
            context.fill(Path(fullRect), with: .color(.black.opacity(0.4)))
            
            // Calculate the box rectangle in view coordinates
            let boxX = offset.x + (box.position.x - box.size.width / 2) * containerSize.width
            let boxY = offset.y + (box.position.y - box.size.height / 2) * containerSize.height
            let boxW = box.size.width * containerSize.width
            let boxH = box.size.height * containerSize.height
            let boxRect = CGRect(x: boxX, y: boxY, width: boxW, height: boxH)
            
            // Cut out the box area (clear the dim inside the box)
            context.blendMode = .destinationOut
            context.fill(Path(boxRect), with: .color(.white))
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Insurance Payment Row

struct InsurancePaymentRow: View {
    let payment: InsurancePayment
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: payment.transactionType.icon)
                .font(.title3)
                .foregroundColor(Color("BrandCyan"))
                .frame(width: 36, height: 36)
                .background(Color("BrandCyan").opacity(0.1))
                .cornerRadius(8)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(payment.payerName)
                    .font(.subheadline).fontWeight(.medium)
                HStack(spacing: 4) {
                    Text(payment.transactionType.rawValue)
                        .font(.caption2).foregroundColor(.secondary)
                    if let check = payment.checkNumber, !check.isEmpty {
                        Text("•").font(.caption2).foregroundColor(.secondary)
                        Text("#\(check)").font(.caption2).foregroundColor(.secondary)
                    }
                }
                Text(payment.paymentDate, style: .date)
                    .font(.caption2).foregroundColor(Color(.tertiaryLabel))
            }
            
            Spacer()
            
            Text(payment.amount, format: .currency(code: "USD"))
                .font(.subheadline).fontWeight(.semibold).foregroundColor(.green)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Patient Payment Row

struct PatientPaymentRow: View {
    let payment: PatientPayment
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: payment.paymentMethod.icon)
                .font(.title3)
                .foregroundColor(.green)
                .frame(width: 36, height: 36)
                .background(Color.green.opacity(0.1))
                .cornerRadius(8)
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(payment.paymentMethod.rawValue)
                        .font(.subheadline).fontWeight(.medium)
                    if let conf = payment.confirmationNumber, !conf.isEmpty {
                        Text("•").font(.caption2).foregroundColor(.secondary)
                        Text("#\(conf)").font(.caption2).foregroundColor(.secondary)
                    }
                }
                if let provider = payment.paidToProvider, !provider.isEmpty {
                    Text("Paid to: \(provider)")
                        .font(.caption2).foregroundColor(.secondary)
                }
                Text(payment.paymentDate, style: .date)
                    .font(.caption2).foregroundColor(Color(.tertiaryLabel))
            }
            
            Spacer()
            
            Text(payment.amount, format: .currency(code: "USD"))
                .font(.subheadline).fontWeight(.semibold).foregroundColor(.green)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Record Insurance Payment View

struct RecordInsurancePaymentView: View {
    let claim: Claim
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var patientDataService: PatientDataService
    
    @State private var payerName = ""
    @State private var paymentAmount = ""
    @State private var paymentDate = Date()
    @State private var checkNumber = ""
    @State private var transactionType: InsurancePayment.TransactionType = .check
    @State private var eobReference = ""
    @State private var notes = ""
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Payer Information") {
                    TextField("Insurance Company Name", text: $payerName)
                    Picker("Transaction Type", selection: $transactionType) {
                        ForEach(InsurancePayment.TransactionType.allCases, id: \.self) { type in
                            Label(type.rawValue, systemImage: type.icon).tag(type)
                        }
                    }
                }
                
                Section("Payment Details") {
                    HStack {
                        Text("Amount")
                        Spacer()
                        Text("$")
                        TextField("0.00", text: $paymentAmount)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                    }
                    DatePicker("Payment Date", selection: $paymentDate, displayedComponents: .date)
                    TextField("Check # / Transaction ID", text: $checkNumber)
                    TextField("EOB Reference (Optional)", text: $eobReference)
                }
                
                Section("Notes") {
                    TextField("Optional notes", text: $notes)
                }
                
                Section("Running Totals") {
                    HStack {
                        Text("Previous Insurance Payments")
                        Spacer()
                        Text(claim.totalInsurancePayments, format: .currency(code: "USD"))
                            .foregroundColor(.green)
                    }
                    if let amount = Double(paymentAmount), amount > 0 {
                        HStack {
                            Text("This Payment")
                            Spacer()
                            Text(amount, format: .currency(code: "USD"))
                                .foregroundColor(.green)
                        }
                        HStack {
                            Text("New Total Insurance Paid")
                                .fontWeight(.medium)
                            Spacer()
                            Text(claim.totalInsurancePayments + amount, format: .currency(code: "USD"))
                                .fontWeight(.semibold).foregroundColor(.green)
                        }
                        
                        let charges = claim.lineItems.isEmpty ? claim.billedAmount : claim.lineItemsTotalCharged
                        let newBalance = charges - (claim.totalInsurancePayments + amount) - (claim.adjustmentAmount ?? 0)
                        HStack {
                            Text("Remaining Balance")
                                .fontWeight(.medium)
                            Spacer()
                            Text(max(0, newBalance), format: .currency(code: "USD"))
                                .fontWeight(.semibold)
                                .foregroundColor(newBalance > 0 ? .orange : .green)
                        }
                    }
                }
            }
            .navigationTitle("Insurance Payment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { recordPayment() }
                        .disabled(payerName.isEmpty || paymentAmount.isEmpty)
                }
            }
        }
    }
    
    private func recordPayment() {
        guard let amount = Double(paymentAmount), amount > 0 else { return }
        
        let payment = InsurancePayment(
            payerName: payerName,
            amount: amount,
            paymentDate: paymentDate,
            checkNumber: checkNumber.isEmpty ? nil : checkNumber,
            transactionType: transactionType,
            eobReference: eobReference.isEmpty ? nil : eobReference,
            notes: notes.isEmpty ? nil : notes
        )
        
        var updated = claim
        updated.insurancePayments.append(payment)
        
        // Update the legacy paidAmount to reflect total insurance payments
        updated.paidAmount = updated.totalInsurancePayments
        updated.updatedAt = Date()
        
        // If balance is zero or negative, mark as paid
        if updated.runningBalance <= 0 {
            updated.status = .paid
        }
        
        patientDataService.saveClaim(updated)
        dismiss()
    }
}

// MARK: - Record Payment View

struct RecordPaymentView: View {
    let claim: Claim
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var patientDataService: PatientDataService
    
    @State private var paymentAmount = ""
    @State private var paymentDate = Date()
    @State private var paymentMethod: PatientPayment.PaymentMethodType = .creditCard
    @State private var confirmationNumber = ""
    @State private var paidToProvider = ""
    @State private var paymentNotes = ""
    
    private var currentBalance: Double {
        claim.runningBalance
    }
    
    private var afterPaymentBalance: Double {
        guard let amount = Double(paymentAmount) else { return currentBalance }
        return max(0, currentBalance - amount)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Payment Details") {
                    HStack {
                        Text("Amount")
                        Spacer()
                        Text("$")
                        TextField("0.00", text: $paymentAmount)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                    }
                    
                    DatePicker("Date", selection: $paymentDate, displayedComponents: .date)
                    
                    Picker("Method", selection: $paymentMethod) {
                        ForEach(PatientPayment.PaymentMethodType.allCases, id: \.self) { method in
                            Label(method.rawValue, systemImage: method.icon).tag(method)
                        }
                    }
                    
                    TextField("Confirmation # (Optional)", text: $confirmationNumber)
                }
                
                Section("Provider") {
                    TextField("Paid To (Provider Name)", text: $paidToProvider)
                }
                
                Section("Notes (Optional)") {
                    TextEditor(text: $paymentNotes)
                        .frame(minHeight: 60)
                }
                
                Section("Balance") {
                    HStack {
                        Text("Current Balance")
                        Spacer()
                        Text(currentBalance, format: .currency(code: "USD"))
                            .foregroundColor(.orange)
                            .fontWeight(.semibold)
                    }
                    if let amount = Double(paymentAmount), amount > 0 {
                        HStack {
                            Text("Payment")
                            Spacer()
                            Text(-amount, format: .currency(code: "USD"))
                                .foregroundColor(.green)
                        }
                        HStack {
                            Text("After Payment")
                            Spacer()
                            Text(afterPaymentBalance, format: .currency(code: "USD"))
                                .foregroundColor(afterPaymentBalance <= 0 ? .green : .primary)
                                .fontWeight(.bold)
                        }
                        if afterPaymentBalance <= 0 {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("Bill will be marked as Paid")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Record Payment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { recordPayment() }
                        .disabled(paymentAmount.isEmpty || Double(paymentAmount) == nil || Double(paymentAmount)! <= 0)
                }
            }
            .onAppear {
                // Pre-fill provider name from claim
                if let name = claim.providerName, !name.isEmpty {
                    paidToProvider = name
                }
            }
        }
    }
    
    private func recordPayment() {
        guard let amount = Double(paymentAmount), amount > 0 else { return }
        
        let payment = PatientPayment(
            amount: amount,
            paymentDate: paymentDate,
            paymentMethod: paymentMethod,
            confirmationNumber: confirmationNumber.isEmpty ? nil : confirmationNumber,
            paidToProvider: paidToProvider.isEmpty ? claim.providerName : paidToProvider,
            notes: paymentNotes.isEmpty ? nil : paymentNotes
        )
        
        var updated = claim
        if updated.patientPayments == nil { updated.patientPayments = [] }
        updated.patientPayments!.append(payment)
        
        // Update patient responsibility to reflect new balance
        updated.patientResponsibility = max(0, updated.runningBalance)
        
        // Auto-set status to paid when balance reaches zero
        if updated.runningBalance <= 0 {
            updated.status = .paid
            updated.paymentDate = paymentDate
            updated.paymentMethod = paymentMethod.rawValue
        }
        
        updated.updatedAt = Date()
        patientDataService.saveClaim(updated)
        dismiss()
    }
}

// MARK: - Dispute Bill View

struct DisputeBillView: View {
    let claim: Claim
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var patientDataService: PatientDataService
    
    @State private var disputeReason = ""
    @State private var selectedReasons: Set<String> = []
    
    let commonReasons = [
        "Incorrect amount charged", "Service not received", "Duplicate charge",
        "Insurance should have paid more", "Incorrect procedure code", "Already paid", "Not my bill", "Other"
    ]
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Select Reason(s)") {
                    ForEach(commonReasons, id: \.self) { reason in
                        Button {
                            if selectedReasons.contains(reason) { selectedReasons.remove(reason) }
                            else { selectedReasons.insert(reason) }
                        } label: {
                            HStack {
                                Text(reason).foregroundColor(.primary)
                                Spacer()
                                if selectedReasons.contains(reason) {
                                    Image(systemName: "checkmark").foregroundColor(.accentColor)
                                }
                            }
                        }
                    }
                }
                Section("Additional Details") {
                    TextEditor(text: $disputeReason).frame(minHeight: 100)
                }
                Section {
                    Text("We'll help you track this dispute and remind you to follow up.")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
            .navigationTitle("Dispute Bill")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit") { submitDispute() }
                        .disabled(selectedReasons.isEmpty && disputeReason.isEmpty)
                }
            }
        }
    }
    
    private func submitDispute() {
        var updated = claim
        updated.status = .appealed
        let reasons = Array(selectedReasons).joined(separator: ", ")
        updated.denialReason = disputeReason.isEmpty ? reasons : "\(reasons)\n\nDetails: \(disputeReason)"
        updated.appealDate = Date()
        updated.updatedAt = Date()
        patientDataService.saveClaim(updated)
        dismiss()
    }
}
