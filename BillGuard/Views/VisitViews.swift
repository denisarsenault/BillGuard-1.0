//
//  VisitViews.swift
//  BillGuard
//
//  Visit management views
//

import SwiftUI

// MARK: - Visit List View

struct VisitListView: View {
    @EnvironmentObject var patientDataService: PatientDataService
    @EnvironmentObject var appState: AppState
    
    let patientId: String
    
    @State private var showingAddVisit = false
    @State private var selectedVisit: Visit?
    @State private var filterStatus: VisitStatus?
    
    private var visits: [Visit] {
        var result = patientDataService.visits(for: patientId)
        if let filter = filterStatus {
            result = result.filter { $0.status == filter }
        }
        return result.sorted { $0.visitDate > $1.visitDate }
    }
    
    private var upcomingVisits: [Visit] {
        visits.filter { $0.visitDate >= Date() && $0.status != .cancelled && $0.status != .completed }
            .sorted { $0.visitDate < $1.visitDate }
    }
    
    private var pastVisits: [Visit] {
        visits.filter { $0.visitDate < Date() || $0.status == .completed || $0.status == .cancelled }
    }
    
    var body: some View {
        Group {
            if visits.isEmpty && filterStatus == nil {
                emptyState
            } else {
                visitList
            }
        }
        .navigationTitle("Visits").brandToolbar(title: "Visits", showPatient: true)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddVisit = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddVisit) {
            AddVisitView(patientId: patientId)
                .environmentObject(patientDataService)
                .environmentObject(appState)
        }
        .sheet(item: $selectedVisit) { visit in
            VisitDetailView(visit: visit)
                .environmentObject(patientDataService)
                .environmentObject(appState)
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("No Visits")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Track medical visits, appointments, and follow-ups.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Button {
                showingAddVisit = true
            } label: {
                Label("Add Visit", systemImage: "plus.circle.fill")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 10)
        }
    }
    
    private var visitList: some View {
        List {
            // Upcoming
            if !upcomingVisits.isEmpty {
                Section(header: Text("Upcoming")) {
                    ForEach(upcomingVisits) { visit in
                        VisitRow(visit: visit)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedVisit = visit
                            }
                    }
                    .onDelete { offsets in
                        deleteVisits(at: offsets, from: upcomingVisits)
                    }
                }
            }
            
            // Past
            if !pastVisits.isEmpty {
                Section(header: Text("Past Visits")) {
                    ForEach(pastVisits) { visit in
                        VisitRow(visit: visit)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedVisit = visit
                            }
                    }
                    .onDelete { offsets in
                        deleteVisits(at: offsets, from: pastVisits)
                    }
                }
            }
            
            if visits.isEmpty {
                Text("No visits match the current filter.")
                    .foregroundColor(.secondary)
                    .italic()
            }
        }
        .listStyle(.insetGrouped)
    }
    
    private func deleteVisits(at offsets: IndexSet, from list: [Visit]) {
        for index in offsets {
            patientDataService.deleteVisit(list[index])
        }
    }
}

// MARK: - Visit Row

struct VisitRow: View {
    let visit: Visit
    
    var body: some View {
        HStack(spacing: 12) {
            // Visit type icon
            Image(systemName: visit.visitType.icon)
                .font(.title3)
                .foregroundColor(statusColor)
                .frame(width: 36, height: 36)
                .background(
                    Circle()
                        .fill(statusColor.opacity(0.1))
                )
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(visit.visitType.rawValue)
                        .font(.headline)
                    
                    Text(visit.status.rawValue)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(statusColor.opacity(0.15))
                        )
                        .foregroundColor(statusColor)
                }
                
                if let provider = visit.providerName {
                    Text(provider)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .font(.caption2)
                    Text(visit.visitDate.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                }
                .foregroundColor(.secondary)
                
                if let reason = visit.reasonForVisit, !reason.isEmpty {
                    Text(reason)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            // Follow-up indicator
            if visit.followUpRequired {
                Image(systemName: "arrow.clockwise.circle.fill")
                    .foregroundColor(.orange)
                    .font(.caption)
            }
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
    
    private var statusColor: Color {
        switch visit.status {
        case .scheduled, .confirmed: return .blue
        case .checkedIn, .inProgress: return .purple
        case .completed: return .green
        case .cancelled, .noShow: return .red
        case .rescheduled: return .orange
        }
    }
}

// MARK: - Visit Detail View

struct VisitDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var patientDataService: PatientDataService
    @EnvironmentObject var appState: AppState
    
    @State var visit: Visit
    
    private var linkedClaims: [Claim] {
        visit.claimIds.compactMap { claimId in
            patientDataService.patients
                .flatMap { patientDataService.claims(for: $0.id) }
                .first { $0.id == claimId }
        }
    }
    
    var body: some View {
        NavigationStack {
            List {
                // Visit Info
                Section(header: Text("Visit Information")) {
                    row("Type", visit.visitType.rawValue)
                    row("Status", visit.status.rawValue)
                    row("Date", visit.visitDate.formatted(date: .long, time: .shortened))
                    
                    if let provider = visit.providerName {
                        row("Provider", provider)
                    }
                    if let providerType = visit.providerType {
                        row("Provider Type", providerType.rawValue)
                    }
                }
                
                // Reason & Diagnosis
                if visit.reasonForVisit != nil || visit.primaryDiagnosis != nil || !visit.diagnosisCodes.isEmpty {
                    Section(header: Text("Diagnosis")) {
                        if let reason = visit.reasonForVisit {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Reason for Visit")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(reason)
                            }
                        }
                        
                        if let diagnosis = visit.primaryDiagnosis {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Primary Diagnosis")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(diagnosis)
                            }
                        }
                        
                        if !visit.diagnosisCodes.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Diagnosis Codes")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                FlowLayout(spacing: 4) {
                                    ForEach(visit.diagnosisCodes, id: \.self) { code in
                                        Text(code)
                                            .font(.caption)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Capsule().fill(Color("BrandCyan").opacity(0.1)))
                                            .foregroundColor(.blue)
                                    }
                                }
                            }
                        }
                        
                        if !visit.procedureCodes.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Procedure Codes")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                FlowLayout(spacing: 4) {
                                    ForEach(visit.procedureCodes, id: \.self) { code in
                                        Text(code)
                                            .font(.caption)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Capsule().fill(Color.purple.opacity(0.1)))
                                            .foregroundColor(.purple)
                                    }
                                }
                            }
                        }
                    }
                }
                
                // Insurance & Copay
                if visit.copayAmount != nil {
                    Section(header: Text("Copay")) {
                        if let copay = visit.copayAmount {
                            HStack {
                                Text("Copay Amount")
                                Spacer()
                                Text(copay, format: .currency(code: "USD"))
                                    .foregroundColor(.secondary)
                            }
                            
                            HStack {
                                Text("Copay Paid")
                                Spacer()
                                Image(systemName: visit.copayPaid ? "checkmark.circle.fill" : "xmark.circle")
                                    .foregroundColor(visit.copayPaid ? .green : .red)
                            }
                        }
                    }
                }
                
                // Linked Bills
                if !linkedClaims.isEmpty {
                    Section(header: Text("Linked Bills")) {
                        ForEach(linkedClaims) { claim in
                            HStack {
                                Image(systemName: "doc.text")
                                    .foregroundColor(.blue)
                                VStack(alignment: .leading) {
                                    Text(claim.providerName ?? "Bill")
                                        .font(.subheadline)
                                    Text(claim.serviceDate.formatted(date: .abbreviated, time: .omitted))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Text(claim.billedAmount, format: .currency(code: "USD"))
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                
                // Follow-up
                if visit.followUpRequired {
                    Section(header: Text("Follow-up")) {
                        HStack {
                            Image(systemName: "arrow.clockwise.circle.fill")
                                .foregroundColor(.orange)
                            Text("Follow-up Required")
                        }
                        
                        if let followUpDate = visit.followUpDate {
                            row("Follow-up Date", followUpDate.formatted(date: .abbreviated, time: .omitted))
                        }
                        
                        if let followUpNotes = visit.followUpNotes {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Follow-up Notes")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(followUpNotes)
                            }
                        }
                    }
                }
                
                // Notes
                if let notes = visit.notes, !notes.isEmpty {
                    Section(header: Text("Notes")) {
                        Text(notes)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(visit.visitType.rawValue)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
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
}

// MARK: - Flow Layout (for tags)

struct FlowLayout: Layout {
    var spacing: CGFloat = 4
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(proposal: proposal, subviews: subviews)
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }
    
    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (positions: [CGPoint], size: CGSize) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var maxY: CGFloat = 0
        var rowHeight: CGFloat = 0
        
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            maxY = max(maxY, y + size.height)
            x += size.width + spacing
        }
        
        return (positions, CGSize(width: maxWidth, height: maxY))
    }
}

// MARK: - Add Visit View

struct AddVisitView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var patientDataService: PatientDataService
    @EnvironmentObject var appState: AppState
    
    let patientId: String
    
    @State private var visitDate = Date()
    @State private var visitType: VisitType = .officeVisit
    @State private var status: VisitStatus = .scheduled
    @State private var reasonForVisit = ""
    @State private var primaryDiagnosis = ""
    @State private var diagnosisCodesText = ""
    @State private var procedureCodesText = ""
    
    // Provider
    @State private var selectedProvider: Provider?
    @State private var showingProviderPicker = false
    @State private var customProviderName = ""
    
    // Insurance
    @State private var selectedPolicyId: String?
    @State private var copayAmount = ""
    @State private var copayPaid = false
    
    // Follow-up
    @State private var followUpRequired = false
    @State private var followUpDate = Date().addingTimeInterval(7 * 24 * 3600)
    @State private var followUpNotes = ""
    
    @State private var notes = ""
    
    private var availablePolicies: [InsurancePolicy] {
        patientDataService.policies(for: patientId).filter { $0.isActive }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                // Visit Details
                Section(header: Text("Visit Details")) {
                    DatePicker("Date & Time", selection: $visitDate)
                    
                    Picker("Visit Type", selection: $visitType) {
                        ForEach(VisitType.allCases, id: \.self) { type in
                            Label(type.rawValue, systemImage: type.icon).tag(type)
                        }
                    }
                    
                    Picker("Status", selection: $status) {
                        ForEach(VisitStatus.allCases, id: \.self) { s in
                            Text(s.rawValue).tag(s)
                        }
                    }
                }
                
                // Provider
                Section(header: Text("Provider")) {
                    if let provider = selectedProvider {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(provider.name)
                                    .fontWeight(.medium)
                                Text(provider.providerType.rawValue)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Button("Change") {
                                showingProviderPicker = true
                            }
                        }
                    } else {
                        Button("Select Provider") {
                            showingProviderPicker = true
                        }
                        
                        TextField("Or enter provider name", text: $customProviderName)
                    }
                }
                
                // Reason & Diagnosis
                Section(header: Text("Reason & Diagnosis")) {
                    TextField("Reason for Visit", text: $reasonForVisit)
                    TextField("Primary Diagnosis", text: $primaryDiagnosis)
                    TextField("Diagnosis Codes (comma separated)", text: $diagnosisCodesText)
                        .autocapitalization(.allCharacters)
                    TextField("Procedure Codes (comma separated)", text: $procedureCodesText)
                        .autocapitalization(.allCharacters)
                }
                
                // Insurance & Copay
                Section(header: Text("Insurance & Copay")) {
                    if !availablePolicies.isEmpty {
                        Picker("Insurance Policy", selection: $selectedPolicyId) {
                            Text("None").tag(nil as String?)
                            ForEach(availablePolicies) { policy in
                                Text("\(policy.policyType.rawValue) - \(policy.memberId)")
                                    .tag(policy.id as String?)
                            }
                        }
                    }
                    
                    HStack {
                        Text("Copay")
                        Spacer()
                        TextField("$0.00", text: $copayAmount)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                    }
                    
                    Toggle("Copay Paid", isOn: $copayPaid)
                }
                
                // Follow-up
                Section(header: Text("Follow-up")) {
                    Toggle("Follow-up Required", isOn: $followUpRequired)
                    
                    if followUpRequired {
                        DatePicker("Follow-up Date", selection: $followUpDate, displayedComponents: .date)
                        TextField("Follow-up Notes", text: $followUpNotes)
                    }
                }
                
                // Notes
                Section(header: Text("Notes")) {
                    TextEditor(text: $notes)
                        .frame(minHeight: 60)
                }
            }
            .navigationTitle("Add Visit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveVisit()
                    }
                    .disabled(selectedProvider == nil && customProviderName.isEmpty)
                }
            }
            .sheet(isPresented: $showingProviderPicker) {
                ProviderPickerView(selectedProvider: $selectedProvider)
                    .environmentObject(patientDataService)
            }
        }
    }
    
    private func saveVisit() {
        let providerId = selectedProvider?.id ?? UUID().uuidString
        let providerName = selectedProvider?.name ?? customProviderName
        let providerType: ProviderType? = selectedProvider?.providerType
        
        // If custom provider, save it
        if selectedProvider == nil && !customProviderName.isEmpty {
            let newProvider = Provider(id: providerId, name: customProviderName, providerType: .other)
            patientDataService.saveProvider(newProvider)
        }
        
        let diagCodes = diagnosisCodesText.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let procCodes = procedureCodesText.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        
        let visit = Visit(
            patientId: patientId,
            providerId: providerId,
            visitDate: visitDate,
            visitType: visitType,
            status: status,
            reasonForVisit: reasonForVisit.isEmpty ? nil : reasonForVisit,
            primaryDiagnosis: primaryDiagnosis.isEmpty ? nil : primaryDiagnosis,
            diagnosisCodes: diagCodes,
            procedureCodes: procCodes,
            providerName: providerName.isEmpty ? nil : providerName,
            providerType: providerType,
            insurancePolicyId: selectedPolicyId,
            copayAmount: Double(copayAmount),
            copayPaid: copayPaid,
            followUpRequired: followUpRequired,
            followUpDate: followUpRequired ? followUpDate : nil,
            followUpNotes: followUpRequired && !followUpNotes.isEmpty ? followUpNotes : nil,
            notes: notes.isEmpty ? nil : notes
        )
        
        patientDataService.saveVisit(visit)
        dismiss()
    }
}

// MARK: - Provider Picker View

struct ProviderPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var patientDataService: PatientDataService
    @Binding var selectedProvider: Provider?
    
    @State private var searchText = ""
    
    private var filteredProviders: [Provider] {
        if searchText.isEmpty {
            return patientDataService.providers
        }
        return patientDataService.providers.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        NavigationStack {
            List(filteredProviders) { provider in
                Button {
                    selectedProvider = provider
                    dismiss()
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(provider.name)
                                .foregroundColor(.primary)
                            Text(provider.providerType.rawValue)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if selectedProvider?.id == provider.id {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search providers")
            .navigationTitle("Select Provider")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .overlay {
                if filteredProviders.isEmpty {
                    ContentUnavailableView("No Providers", systemImage: "building.2", description: Text("Add a provider first from the Providers tab"))
                }
            }
        }
    }
}
