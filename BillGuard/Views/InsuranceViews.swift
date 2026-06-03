//
//  InsuranceViews.swift
//  BillGuard
//
//  Insurance policy management views
//

import SwiftUI

// MARK: - Insurance List View

struct InsuranceListView: View {
    @EnvironmentObject var patientDataService: PatientDataService
    @EnvironmentObject var appState: AppState
    
    let patientId: String
    
    @State private var showingAddPolicy = false
    @State private var selectedPolicy: InsurancePolicy?
    
    private var policies: [InsurancePolicy] {
        patientDataService.policies(for: patientId)
            .sorted { ($0.isPrimary ? 0 : 1) < ($1.isPrimary ? 0 : 1) }
    }
    
    private var patient: Patient? {
        patientDataService.patients.first { $0.id == patientId }
    }
    
    var body: some View {
        Group {
            if policies.isEmpty {
                emptyState
            } else {
                policyList
            }
        }
        .navigationTitle("Insurance").brandToolbar(title: "Insurance", showPatient: true)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddPolicy = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddPolicy) {
            AddInsurancePolicyView(patientId: patientId)
                .environmentObject(patientDataService)
                .environmentObject(appState)
        }
        .sheet(item: $selectedPolicy) { policy in
            InsurancePolicyDetailView(policy: policy)
                .environmentObject(patientDataService)
                .environmentObject(appState)
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("No Insurance Policies")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Add insurance policies to track coverage, deductibles, and copays.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Button {
                showingAddPolicy = true
            } label: {
                Label("Add Policy", systemImage: "plus.circle.fill")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 10)
        }
    }
    
    private var policyList: some View {
        List {
            // Active Policies
            let activePolicies = policies.filter { $0.isActive }
            if !activePolicies.isEmpty {
                Section(header: Text("Active Policies")) {
                    ForEach(activePolicies) { policy in
                        InsurancePolicyRow(policy: policy)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedPolicy = policy
                            }
                    }
                    .onDelete { offsets in
                        deletePolicies(at: offsets, from: activePolicies)
                    }
                }
            }
            
            // Inactive Policies
            let inactivePolicies = policies.filter { !$0.isActive }
            if !inactivePolicies.isEmpty {
                Section(header: Text("Inactive Policies")) {
                    ForEach(inactivePolicies) { policy in
                        InsurancePolicyRow(policy: policy)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedPolicy = policy
                            }
                    }
                    .onDelete { offsets in
                        deletePolicies(at: offsets, from: inactivePolicies)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }
    
    private func deletePolicies(at offsets: IndexSet, from list: [InsurancePolicy]) {
        for index in offsets {
            patientDataService.deletePolicy(list[index])
        }
    }
}

// MARK: - Insurance Policy Row

struct InsurancePolicyRow: View {
    let policy: InsurancePolicy
    
    var body: some View {
        HStack(spacing: 12) {
            // Policy type icon
            Image(systemName: policyIcon)
                .font(.title2)
                .foregroundColor(policy.isActive ? .blue : .gray)
                .frame(width: 40, height: 40)
                .background(
                    Circle()
                        .fill((policy.isActive ? Color("BrandCyan") : Color.gray).opacity(0.1))
                )
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(policy.policyType.rawValue)
                        .font(.headline)
                    
                    if policy.isPrimary {
                        Text("PRIMARY")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color("BrandCyan").opacity(0.15)))
                            .foregroundColor(.blue)
                    }
                }
                
                if let planName = policy.planName {
                    Text(planName)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Text("Member: \(policy.memberId)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                // Deductible progress
                if let deductible = policy.deductible {
                    HStack(spacing: 4) {
                        ProgressView(value: deductible.individualPercentMet)
                            .tint(deductible.individualPercentMet >= 1.0 ? .green : .orange)
                            .frame(width: 60)
                        
                        Text("Deductible: \(deductible.individualMet, format: .currency(code: "USD")) / \(deductible.individual, format: .currency(code: "USD"))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
            
            if !policy.isActive {
                Text("Inactive")
                    .font(.caption)
                    .foregroundColor(.red)
            }
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
    
    private var policyIcon: String {
        switch policy.policyType {
        case .medical: return "stethoscope"
        case .dental: return "mouth.fill"
        case .vision: return "eye.fill"
        case .prescription: return "pills.fill"
        case .medicare: return "heart.text.square.fill"
        case .medicaid: return "heart.text.square"
        case .tricare: return "star.fill"
        default: return "shield.lefthalf.filled"
        }
    }
}

// MARK: - Insurance Policy Detail View

struct InsurancePolicyDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var patientDataService: PatientDataService
    @EnvironmentObject var appState: AppState
    
    @State var policy: InsurancePolicy
    @State private var isEditing = false
    
    private var carrier: InsuranceCarrier? {
        patientDataService.insuranceCarriers.first { $0.id == policy.carrierId }
    }
    
    var body: some View {
        NavigationStack {
            List {
                // Insurance Carrier — top of view
                Section {
                    HStack(spacing: 14) {
                        Image(systemName: "shield.fill")
                            .font(.title)
                            .foregroundColor(Color("BrandCyan"))
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(carrier?.name ?? "Unknown Carrier")
                                .font(.title3)
                                .fontWeight(.bold)
                            if let phone = carrier?.phones.first?.number, !phone.isEmpty {
                                Label(phone, systemImage: "phone")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            if let website = carrier?.website, !website.isEmpty {
                                Label(website, systemImage: "globe")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                
                // Status Banner
                if !policy.isActive {
                    Section {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("This policy is no longer active")
                                .foregroundColor(.orange)
                        }
                    }
                }
                
                // Policy Info
                Section(header: Text("Policy Information")) {
                    row("Type", policy.policyType.rawValue)
                    if let planType = policy.planType {
                        row("Plan Type", planType.rawValue)
                    }
                    if let planName = policy.planName {
                        row("Plan Name", planName)
                    }
                    if let coverage = policy.coverageLevel {
                        row("Coverage Level", coverage.rawValue)
                    }
                    if policy.isPrimary {
                        row("Priority", "Primary")
                    } else if let cob = policy.coordinationOfBenefits {
                        row("Priority", cob == 2 ? "Secondary" : "Tertiary")
                    }
                }
                
                // Member Info
                Section(header: Text("Member Information")) {
                    row("Member ID", policy.memberId)
                    if let group = policy.groupNumber {
                        row("Group Number", group)
                    }
                    if let policyNum = policy.policyNumber {
                        row("Policy Number", policyNum)
                    }
                }
                
                // Pharmacy Info
                if policy.rxBin != nil || policy.rxPcn != nil || policy.rxGroup != nil {
                    Section(header: Text("Pharmacy Benefits")) {
                        if let bin = policy.rxBin { row("RX BIN", bin) }
                        if let pcn = policy.rxPcn { row("RX PCN", pcn) }
                        if let group = policy.rxGroup { row("RX Group", group) }
                    }
                }
                
                // Coverage Dates
                Section(header: Text("Coverage Dates")) {
                    if let effDate = policy.effectiveDate {
                        row("Effective Date", effDate.formatted(date: .abbreviated, time: .omitted))
                    }
                    if let termDate = policy.terminationDate {
                        row("Termination Date", termDate.formatted(date: .abbreviated, time: .omitted))
                    }
                    row("Status", policy.isActive ? "Active" : "Inactive")
                }
                
                // Cost Sharing
                Section(header: Text("Cost Sharing")) {
                    if let deductible = policy.deductible {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Individual Deductible")
                                Spacer()
                                Text("\(deductible.individualMet, format: .currency(code: "USD")) / \(deductible.individual, format: .currency(code: "USD"))")
                                    .foregroundColor(.secondary)
                            }
                            ProgressView(value: deductible.individualPercentMet)
                                .tint(deductible.individualPercentMet >= 1.0 ? .green : .orange)
                            
                            if let family = deductible.family, let familyMet = deductible.familyMet {
                                Divider()
                                HStack {
                                    Text("Family Deductible")
                                    Spacer()
                                    Text("\(familyMet, format: .currency(code: "USD")) / \(family, format: .currency(code: "USD"))")
                                        .foregroundColor(.secondary)
                                }
                                ProgressView(value: family > 0 ? min(1.0, familyMet / family) : 0)
                                    .tint(familyMet >= family ? .green : .orange)
                            }
                        }
                    }
                    
                    if let coinsurance = policy.coinsurance {
                        row("Coinsurance", "\(Int(coinsurance * 100))%")
                    }
                    
                    if let oopMax = policy.outOfPocketMax {
                        let oopMet = policy.outOfPocketMet ?? 0
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Out-of-Pocket Max")
                                Spacer()
                                Text("\(oopMet, format: .currency(code: "USD")) / \(oopMax, format: .currency(code: "USD"))")
                                    .foregroundColor(.secondary)
                            }
                            ProgressView(value: oopMax > 0 ? min(1.0, oopMet / oopMax) : 0)
                                .tint(oopMet >= oopMax ? .green : .blue)
                        }
                    }
                }
                
                // Copays
                if let copay = policy.copay {
                    Section(header: Text("Copays")) {
                        if let pc = copay.primaryCare { row("Primary Care", pc, format: .currency(code: "USD")) }
                        if let sp = copay.specialist { row("Specialist", sp, format: .currency(code: "USD")) }
                        if let uc = copay.urgentCare { row("Urgent Care", uc, format: .currency(code: "USD")) }
                        if let er = copay.emergencyRoom { row("Emergency Room", er, format: .currency(code: "USD")) }
                        if let gd = copay.genericDrug { row("Generic Drug", gd, format: .currency(code: "USD")) }
                        if let bd = copay.brandDrug { row("Brand Drug", bd, format: .currency(code: "USD")) }
                        if let sd = copay.specialtyDrug { row("Specialty Drug", sd, format: .currency(code: "USD")) }
                        if let prev = copay.preventiveCare { row("Preventive Care", prev, format: .currency(code: "USD")) }
                        if let lab = copay.labWork { row("Lab Work", lab, format: .currency(code: "USD")) }
                        if let img = copay.imaging { row("Imaging", img, format: .currency(code: "USD")) }
                        if let mh = copay.mentalHealth { row("Mental Health", mh, format: .currency(code: "USD")) }
                        if let pt = copay.physicalTherapy { row("Physical Therapy", pt, format: .currency(code: "USD")) }
                    }
                }
                
                // Subscriber Info
                if policy.subscriberName != nil || policy.subscriberEmployer != nil {
                    Section(header: Text("Subscriber Information")) {
                        if let name = policy.subscriberName {
                            row("Subscriber Name", name)
                        }
                        if let rel = policy.subscriberRelationship {
                            row("Relationship", rel.rawValue)
                        }
                        if let employer = policy.subscriberEmployer {
                            row("Employer", employer)
                        }
                    }
                }
                
                // Carrier Info
                if let carrier = carrier {
                    Section(header: Text("Insurance Carrier")) {
                        row("Carrier", carrier.name)
                        if let phone = carrier.primaryPhone {
                            Button {
                                if let url = URL(string: "tel:\(phone.filter { $0.isNumber || $0 == "+" })") {
                                    UIApplication.shared.open(url)
                                }
                            } label: {
                                HStack {
                                    Text("Customer Service")
                                    Spacer()
                                    Text(phone)
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                        if let website = carrier.website {
                            Link(destination: URL(string: website) ?? URL(string: "https://")!) {
                                HStack {
                                    Text("Website")
                                    Spacer()
                                    Text(website)
                                        .foregroundColor(.blue)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                }
                
                // Notes
                if let notes = policy.notes, !notes.isEmpty {
                    Section(header: Text("Notes")) {
                        Text(notes)
                            .font(.body)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Insurance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Edit") {
                        isEditing = true
                    }
                }
            }
            .sheet(isPresented: $isEditing) {
                EditInsurancePolicyView(policy: $policy)
                    .environmentObject(patientDataService)
                    .environmentObject(appState)
            }
        }
    }
    
    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
        }
    }
    
    private func row(_ label: String, _ value: Double, format: FloatingPointFormatStyle<Double>.Currency) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value, format: format)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Add Insurance Policy View

struct AddInsurancePolicyView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var patientDataService: PatientDataService
    @EnvironmentObject var appState: AppState
    
    let patientId: String
    
    // Basic Info
    @State private var policyType: PolicyType = .medical
    @State private var planType: PlanType = .ppo
    @State private var planName = ""
    @State private var coverageLevel: CoverageLevel = .individual
    @State private var isPrimary = true
    
    // Member Info
    @State private var memberId = ""
    @State private var groupNumber = ""
    @State private var policyNumber = ""
    
    // Pharmacy
    @State private var rxBin = ""
    @State private var rxPcn = ""
    @State private var rxGroup = ""
    
    // Carrier
    @State private var selectedCarrier: InsuranceCarrier?
    @State private var showingCarrierPicker = false
    @State private var customCarrierName = ""
    
    // Dates
    @State private var effectiveDate = Date()
    @State private var hasTerminationDate = false
    @State private var terminationDate = Date()
    
    // Cost Sharing
    @State private var deductibleAmount = ""
    @State private var deductibleMet = ""
    @State private var coinsurancePercent = ""
    @State private var outOfPocketMax = ""
    @State private var outOfPocketMet = ""
    
    // Copays
    @State private var showCopays = false
    @State private var copayPrimaryCare = ""
    @State private var copaySpecialist = ""
    @State private var copayUrgentCare = ""
    @State private var copayER = ""
    @State private var copayGenericDrug = ""
    @State private var copayBrandDrug = ""
    
    // Notes
    @State private var notes = ""
    
    var body: some View {
        NavigationStack {
            Form {
                // Carrier Selection
                Section(header: Text("Insurance Carrier")) {
                    if let carrier = selectedCarrier {
                        HStack {
                            Text(carrier.name)
                                .fontWeight(.medium)
                            Spacer()
                            Button("Change") {
                                showingCarrierPicker = true
                            }
                        }
                    } else {
                        Button("Select Carrier") {
                            showingCarrierPicker = true
                        }
                        
                        TextField("Or enter carrier name", text: $customCarrierName)
                    }
                }
                
                // Policy Type
                Section(header: Text("Policy Details")) {
                    Picker("Policy Type", selection: $policyType) {
                        ForEach(PolicyType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    
                    Picker("Plan Type", selection: $planType) {
                        ForEach(PlanType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    
                    TextField("Plan Name (optional)", text: $planName)
                    
                    Picker("Coverage Level", selection: $coverageLevel) {
                        ForEach(CoverageLevel.allCases, id: \.self) { level in
                            Text(level.rawValue).tag(level)
                        }
                    }
                    
                    Toggle("Primary Insurance", isOn: $isPrimary)
                }
                
                // Member Info
                Section(header: Text("Member Information")) {
                    TextField("Member ID *", text: $memberId)
                    TextField("Group Number", text: $groupNumber)
                    TextField("Policy Number", text: $policyNumber)
                }
                
                // Pharmacy Benefits
                Section(header: Text("Pharmacy Benefits (optional)")) {
                    TextField("RX BIN", text: $rxBin)
                    TextField("RX PCN", text: $rxPcn)
                    TextField("RX Group", text: $rxGroup)
                }
                
                // Coverage Dates
                Section(header: Text("Coverage Dates")) {
                    DatePicker("Effective Date", selection: $effectiveDate, displayedComponents: .date)
                    
                    Toggle("Has Termination Date", isOn: $hasTerminationDate)
                    
                    if hasTerminationDate {
                        DatePicker("Termination Date", selection: $terminationDate, displayedComponents: .date)
                    }
                }
                
                // Cost Sharing
                Section(header: Text("Cost Sharing")) {
                    HStack {
                        Text("Deductible")
                        Spacer()
                        TextField("$0.00", text: $deductibleAmount)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                    }
                    
                    HStack {
                        Text("Deductible Met")
                        Spacer()
                        TextField("$0.00", text: $deductibleMet)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                    }
                    
                    HStack {
                        Text("Coinsurance %")
                        Spacer()
                        TextField("20", text: $coinsurancePercent)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                        Text("%")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Out-of-Pocket Max")
                        Spacer()
                        TextField("$0.00", text: $outOfPocketMax)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                    }
                    
                    HStack {
                        Text("OOP Met")
                        Spacer()
                        TextField("$0.00", text: $outOfPocketMet)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                    }
                }
                
                // Copays
                Section(header: Text("Copays")) {
                    DisclosureGroup("Set Copay Amounts", isExpanded: $showCopays) {
                        copayField("Primary Care", $copayPrimaryCare)
                        copayField("Specialist", $copaySpecialist)
                        copayField("Urgent Care", $copayUrgentCare)
                        copayField("Emergency Room", $copayER)
                        copayField("Generic Drug", $copayGenericDrug)
                        copayField("Brand Drug", $copayBrandDrug)
                    }
                }
                
                // Notes
                Section(header: Text("Notes")) {
                    TextEditor(text: $notes)
                        .frame(minHeight: 60)
                }
            }
            .navigationTitle("Add Insurance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        savePolicy()
                    }
                    .disabled(memberId.isEmpty && selectedCarrier == nil && customCarrierName.isEmpty)
                }
            }
            .sheet(isPresented: $showingCarrierPicker) {
                CarrierPickerView(selectedCarrier: $selectedCarrier)
                    .environmentObject(patientDataService)
            }
        }
    }
    
    private func copayField(_ label: String, _ value: Binding<String>) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("$0", text: value)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
        }
    }
    
    private func savePolicy() {
        // Create or find carrier
        var carrierId: String
        if let carrier = selectedCarrier {
            carrierId = carrier.id
        } else if !customCarrierName.isEmpty {
            let newCarrier = InsuranceCarrier(name: customCarrierName)
            patientDataService.saveCarrier(newCarrier)
            carrierId = newCarrier.id
        } else {
            carrierId = ""
        }
        
        // Build copay structure
        var copay: CopayStructure? = nil
        if showCopays {
            copay = CopayStructure(
                primaryCare: Double(copayPrimaryCare),
                specialist: Double(copaySpecialist),
                urgentCare: Double(copayUrgentCare),
                emergencyRoom: Double(copayER),
                genericDrug: Double(copayGenericDrug),
                brandDrug: Double(copayBrandDrug)
            )
        }
        
        // Build deductible
        var deductible: DeductibleInfo? = nil
        if let dedAmt = Double(deductibleAmount), dedAmt > 0 {
            deductible = DeductibleInfo(
                individual: dedAmt,
                individualMet: Double(deductibleMet) ?? 0
            )
        }
        
        let policy = InsurancePolicy(
            patientId: patientId,
            carrierId: carrierId,
            policyType: policyType,
            planType: planType,
            planName: planName.isEmpty ? nil : planName,
            coverageLevel: coverageLevel,
            memberId: memberId,
            groupNumber: groupNumber.isEmpty ? nil : groupNumber,
            policyNumber: policyNumber.isEmpty ? nil : policyNumber,
            rxBin: rxBin.isEmpty ? nil : rxBin,
            rxPcn: rxPcn.isEmpty ? nil : rxPcn,
            rxGroup: rxGroup.isEmpty ? nil : rxGroup,
            effectiveDate: effectiveDate,
            terminationDate: hasTerminationDate ? terminationDate : nil,
            copay: copay,
            deductible: deductible,
            coinsurance: Double(coinsurancePercent).map { $0 / 100.0 },
            outOfPocketMax: Double(outOfPocketMax),
            outOfPocketMet: Double(outOfPocketMet),
            isPrimary: isPrimary
        )
        
        patientDataService.savePolicy(policy)
        dismiss()
    }
}

// MARK: - Carrier Picker View

struct CarrierPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var patientDataService: PatientDataService
    @Binding var selectedCarrier: InsuranceCarrier?
    
    @State private var searchText = ""
    
    private var allCarriers: [InsuranceCarrier] {
        let existing = patientDataService.insuranceCarriers
        let common = InsuranceCarrier.commonCarriers.filter { common in
            !existing.contains { $0.name == common.name }
        }
        return existing + common
    }
    
    private var filteredCarriers: [InsuranceCarrier] {
        if searchText.isEmpty {
            return allCarriers
        }
        return allCarriers.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            ($0.shortName?.localizedCaseInsensitiveContains(searchText) == true)
        }
    }
    
    var body: some View {
        NavigationStack {
            List(filteredCarriers) { carrier in
                Button {
                    selectedCarrier = carrier
                    dismiss()
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(carrier.name)
                                .font(.body)
                                .foregroundColor(.primary)
                            if let phone = carrier.primaryPhone {
                                Text(phone)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                        if selectedCarrier?.id == carrier.id {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search carriers")
            .navigationTitle("Select Carrier")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Edit Insurance Policy View

struct EditInsurancePolicyView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var patientDataService: PatientDataService
    @EnvironmentObject var appState: AppState
    
    @Binding var policy: InsurancePolicy
    
    // Basic Info
    @State private var policyType: PolicyType
    @State private var planType: PlanType
    @State private var planName: String
    @State private var coverageLevel: CoverageLevel
    @State private var isPrimary: Bool
    
    // Member Info
    @State private var memberId: String
    @State private var groupNumber: String
    @State private var policyNumber: String
    
    // Pharmacy
    @State private var rxBin: String
    @State private var rxPcn: String
    @State private var rxGroup: String
    
    // Carrier
    @State private var selectedCarrier: InsuranceCarrier?
    @State private var showingCarrierPicker = false
    
    // Dates
    @State private var effectiveDate: Date
    @State private var hasTerminationDate: Bool
    @State private var terminationDate: Date
    
    // Cost Sharing
    @State private var deductibleAmount: String
    @State private var deductibleMet: String
    @State private var coinsurancePercent: String
    @State private var outOfPocketMax: String
    @State private var outOfPocketMet: String
    
    // Copays
    @State private var showCopays: Bool
    @State private var copayPrimaryCare: String
    @State private var copaySpecialist: String
    @State private var copayUrgentCare: String
    @State private var copayER: String
    @State private var copayGenericDrug: String
    @State private var copayBrandDrug: String
    
    // Notes
    @State private var notes: String
    
    init(policy: Binding<InsurancePolicy>) {
        _policy = policy
        let p = policy.wrappedValue
        _policyType = State(initialValue: p.policyType)
        _planType = State(initialValue: p.planType ?? .ppo)
        _planName = State(initialValue: p.planName ?? "")
        _coverageLevel = State(initialValue: p.coverageLevel ?? .individual)
        _isPrimary = State(initialValue: p.isPrimary)
        _memberId = State(initialValue: p.memberId)
        _groupNumber = State(initialValue: p.groupNumber ?? "")
        _policyNumber = State(initialValue: p.policyNumber ?? "")
        _rxBin = State(initialValue: p.rxBin ?? "")
        _rxPcn = State(initialValue: p.rxPcn ?? "")
        _rxGroup = State(initialValue: p.rxGroup ?? "")
        _effectiveDate = State(initialValue: p.effectiveDate ?? Date())
        _hasTerminationDate = State(initialValue: p.terminationDate != nil)
        _terminationDate = State(initialValue: p.terminationDate ?? Date())
        _deductibleAmount = State(initialValue: p.deductible.map { String(format: "%.2f", $0.individual) } ?? "")
        _deductibleMet = State(initialValue: p.deductible.map { String(format: "%.2f", $0.individualMet) } ?? "")
        _coinsurancePercent = State(initialValue: p.coinsurance.map { String(Int($0 * 100)) } ?? "")
        _outOfPocketMax = State(initialValue: p.outOfPocketMax.map { String(format: "%.2f", $0) } ?? "")
        _outOfPocketMet = State(initialValue: p.outOfPocketMet.map { String(format: "%.2f", $0) } ?? "")
        _showCopays = State(initialValue: p.copay != nil)
        _copayPrimaryCare = State(initialValue: p.copay?.primaryCare.map { String(format: "%.0f", $0) } ?? "")
        _copaySpecialist = State(initialValue: p.copay?.specialist.map { String(format: "%.0f", $0) } ?? "")
        _copayUrgentCare = State(initialValue: p.copay?.urgentCare.map { String(format: "%.0f", $0) } ?? "")
        _copayER = State(initialValue: p.copay?.emergencyRoom.map { String(format: "%.0f", $0) } ?? "")
        _copayGenericDrug = State(initialValue: p.copay?.genericDrug.map { String(format: "%.0f", $0) } ?? "")
        _copayBrandDrug = State(initialValue: p.copay?.brandDrug.map { String(format: "%.0f", $0) } ?? "")
        _notes = State(initialValue: p.notes ?? "")
        _selectedCarrier = State(initialValue: nil)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Insurance Carrier")) {
                    if let carrier = selectedCarrier {
                        HStack {
                            Text(carrier.name).fontWeight(.medium)
                            Spacer()
                            Button("Change") { showingCarrierPicker = true }
                        }
                    } else {
                        let currentCarrier = patientDataService.insuranceCarriers.first { $0.id == policy.carrierId }
                        HStack {
                            Text(currentCarrier?.name ?? "Unknown Carrier").fontWeight(.medium)
                            Spacer()
                            Button("Change") { showingCarrierPicker = true }
                        }
                    }
                }
                
                Section(header: Text("Policy Details")) {
                    Picker("Policy Type", selection: $policyType) {
                        ForEach(PolicyType.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    Picker("Plan Type", selection: $planType) {
                        ForEach(PlanType.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    TextField("Plan Name", text: $planName)
                    Picker("Coverage Level", selection: $coverageLevel) {
                        ForEach(CoverageLevel.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    Toggle("Primary Insurance", isOn: $isPrimary)
                }
                
                Section(header: Text("Member Information")) {
                    TextField("Member ID", text: $memberId)
                    TextField("Group Number", text: $groupNumber)
                    TextField("Policy Number", text: $policyNumber)
                }
                
                Section(header: Text("Pharmacy Benefits")) {
                    TextField("RX BIN", text: $rxBin)
                    TextField("RX PCN", text: $rxPcn)
                    TextField("RX Group", text: $rxGroup)
                }
                
                Section(header: Text("Coverage Dates")) {
                    DatePicker("Effective Date", selection: $effectiveDate, displayedComponents: .date)
                    Toggle("Has Termination Date", isOn: $hasTerminationDate)
                    if hasTerminationDate {
                        DatePicker("Termination Date", selection: $terminationDate, displayedComponents: .date)
                    }
                }
                
                Section(header: Text("Cost Sharing")) {
                    costField("Deductible", $deductibleAmount)
                    costField("Deductible Met", $deductibleMet)
                    HStack {
                        Text("Coinsurance %")
                        Spacer()
                        TextField("20", text: $coinsurancePercent)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                        Text("%").foregroundColor(.secondary)
                    }
                    costField("Out-of-Pocket Max", $outOfPocketMax)
                    costField("OOP Met", $outOfPocketMet)
                }
                
                Section(header: Text("Copays")) {
                    DisclosureGroup("Copay Amounts", isExpanded: $showCopays) {
                        copayField("Primary Care", $copayPrimaryCare)
                        copayField("Specialist", $copaySpecialist)
                        copayField("Urgent Care", $copayUrgentCare)
                        copayField("Emergency Room", $copayER)
                        copayField("Generic Drug", $copayGenericDrug)
                        copayField("Brand Drug", $copayBrandDrug)
                    }
                }
                
                Section(header: Text("Notes")) {
                    TextEditor(text: $notes)
                        .frame(minHeight: 60)
                }
                
                Section {
                    Button(role: .destructive) {
                        patientDataService.deletePolicy(policy)
                        dismiss()
                    } label: {
                        HStack {
                            Spacer()
                            Label("Delete Policy", systemImage: "trash")
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("Edit Insurance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveChanges() }
                        .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showingCarrierPicker) {
                CarrierPickerView(selectedCarrier: $selectedCarrier)
                    .environmentObject(patientDataService)
            }
        }
    }
    
    private func costField(_ label: String, _ value: Binding<String>) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("$0.00", text: value)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 100)
        }
    }
    
    private func copayField(_ label: String, _ value: Binding<String>) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("$0", text: value)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
        }
    }
    
    private func saveChanges() {
        if let carrier = selectedCarrier {
            policy.carrierId = carrier.id
        }
        
        policy.policyType = policyType
        policy.planType = planType
        policy.planName = planName.isEmpty ? nil : planName
        policy.coverageLevel = coverageLevel
        policy.isPrimary = isPrimary
        policy.memberId = memberId
        policy.groupNumber = groupNumber.isEmpty ? nil : groupNumber
        policy.policyNumber = policyNumber.isEmpty ? nil : policyNumber
        policy.rxBin = rxBin.isEmpty ? nil : rxBin
        policy.rxPcn = rxPcn.isEmpty ? nil : rxPcn
        policy.rxGroup = rxGroup.isEmpty ? nil : rxGroup
        policy.effectiveDate = effectiveDate
        policy.terminationDate = hasTerminationDate ? terminationDate : nil
        policy.notes = notes.isEmpty ? nil : notes
        
        if let dedAmt = Double(deductibleAmount), dedAmt > 0 {
            policy.deductible = DeductibleInfo(
                individual: dedAmt,
                individualMet: Double(deductibleMet) ?? 0
            )
        } else {
            policy.deductible = nil
        }
        
        policy.coinsurance = Double(coinsurancePercent).map { $0 / 100.0 }
        policy.outOfPocketMax = Double(outOfPocketMax)
        policy.outOfPocketMet = Double(outOfPocketMet)
        
        if showCopays {
            policy.copay = CopayStructure(
                primaryCare: Double(copayPrimaryCare),
                specialist: Double(copaySpecialist),
                urgentCare: Double(copayUrgentCare),
                emergencyRoom: Double(copayER),
                genericDrug: Double(copayGenericDrug),
                brandDrug: Double(copayBrandDrug)
            )
        } else {
            policy.copay = nil
        }
        
        policy.updatedAt = Date()
        patientDataService.savePolicy(policy)
        dismiss()
    }
}
