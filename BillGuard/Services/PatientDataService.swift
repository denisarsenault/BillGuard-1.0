//
//  PatientDataService.swift
//  BillGuard
//
//  Service for managing patient-related data with local storage
//

import Foundation
import Combine
import CloudKit

@MainActor
class PatientDataService: ObservableObject {
    static let shared = PatientDataService()
    
    // MARK: - Published Data
    @Published var patients: [Patient]
    @Published var insurancePolicies: [InsurancePolicy]
    @Published var insuranceCarriers: [InsuranceCarrier]
    @Published var paymentMethods: [PaymentMethod]
    @Published var providers: [Provider]
    @Published var visits: [Visit]
    @Published var claims: [Claim]
    @Published var scannedDocuments: [ScannedDocument]
    
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    // MARK: - Storage Keys
    private enum StorageKeys {
        static let patients = "billguard_patients"
        static let policies = "billguard_policies"
        static let carriers = "billguard_carriers"
        static let payments = "billguard_payments"
        static let providers = "billguard_providers"
        static let visits = "billguard_visits"
        static let claims = "billguard_claims"
        static let documents = "billguard_documents"
    }
    
    // MARK: - Static loader (no self needed, no @Published triggers)
    
    private static func loadStatic<T: Codable>(key: String) -> [T] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([T].self, from: data)) ?? []
    }
    
    // MARK: - Initialization
    
    private init() {
        let t0 = CFAbsoluteTimeGetCurrent()
        
        let p: [Patient] = Self.loadStatic(key: StorageKeys.patients)
        print("⏱️ [PDS] patients: \(Int((CFAbsoluteTimeGetCurrent()-t0)*1000))ms (\(p.count) items)")
        
        let t1 = CFAbsoluteTimeGetCurrent()
        let ip: [InsurancePolicy] = Self.loadStatic(key: StorageKeys.policies)
        print("⏱️ [PDS] policies: \(Int((CFAbsoluteTimeGetCurrent()-t1)*1000))ms (\(ip.count) items)")
        
        let t2 = CFAbsoluteTimeGetCurrent()
        var ic: [InsuranceCarrier] = Self.loadStatic(key: StorageKeys.carriers)
        print("⏱️ [PDS] carriers: \(Int((CFAbsoluteTimeGetCurrent()-t2)*1000))ms (\(ic.count) items)")
        
        let t3 = CFAbsoluteTimeGetCurrent()
        let pm: [PaymentMethod] = Self.loadStatic(key: StorageKeys.payments)
        print("⏱️ [PDS] payments: \(Int((CFAbsoluteTimeGetCurrent()-t3)*1000))ms (\(pm.count) items)")
        
        let t4 = CFAbsoluteTimeGetCurrent()
        var prov: [Provider] = Self.loadStatic(key: StorageKeys.providers)
        print("⏱️ [PDS] providers: \(Int((CFAbsoluteTimeGetCurrent()-t4)*1000))ms (\(prov.count) items)")
        
        let t5 = CFAbsoluteTimeGetCurrent()
        let v: [Visit] = Self.loadStatic(key: StorageKeys.visits)
        print("⏱️ [PDS] visits: \(Int((CFAbsoluteTimeGetCurrent()-t5)*1000))ms (\(v.count) items)")
        
        let t6 = CFAbsoluteTimeGetCurrent()
        let cl: [Claim] = Self.loadStatic(key: StorageKeys.claims)
        print("⏱️ [PDS] claims: \(Int((CFAbsoluteTimeGetCurrent()-t6)*1000))ms (\(cl.count) items)")
        
        let t7 = CFAbsoluteTimeGetCurrent()
        let docs: [ScannedDocument] = Self.loadStatic(key: StorageKeys.documents)
        print("⏱️ [PDS] documents: \(Int((CFAbsoluteTimeGetCurrent()-t7)*1000))ms (\(docs.count) items)")
        
        // Merge common carriers
        for carrier in InsuranceCarrier.commonCarriers {
            if !ic.contains(where: { $0.name == carrier.name }) {
                ic.append(carrier)
            }
        }
        
        // Sync providers from claims
        for claim in cl {
            guard let providerName = claim.providerName, !providerName.isEmpty else { continue }
            if !prov.contains(where: { $0.name.lowercased() == providerName.lowercased() }) {
                prov.append(Provider(name: providerName, providerType: Self.guessProviderTypeStatic(from: providerName)))
            }
        }
        
        _patients = Published(initialValue: p)
        _insurancePolicies = Published(initialValue: ip)
        _insuranceCarriers = Published(initialValue: ic)
        _paymentMethods = Published(initialValue: pm)
        _providers = Published(initialValue: prov)
        _visits = Published(initialValue: v)
        _claims = Published(initialValue: cl)
        _scannedDocuments = Published(initialValue: docs)
        
        let total = CFAbsoluteTimeGetCurrent() - t0
        print("⏱️ [PDS] TOTAL: \(Int(total*1000))ms")

        refreshFromCloud()   // pull patients & claims from iCloud (best-effort)
    }
    
    private static func guessProviderTypeStatic(from name: String) -> ProviderType {
        let lower = name.lowercased()
        if lower.contains("hospital") || lower.contains("medical center") { return .hospital }
        if lower.contains("emergency") { return .emergencyRoom }
        if lower.contains("urgent") { return .urgentCare }
        if lower.contains("lab") || lower.contains("pathology") || lower.contains("quest") || lower.contains("labcorp") { return .laboratory }
        if lower.contains("imaging") || lower.contains("radiology") || lower.contains("x-ray") || lower.contains("mri") { return .imagingCenter }
        if lower.contains("pharmacy") || lower.contains("rx") { return .pharmacy }
        if lower.contains("dental") || lower.contains("dentist") { return .dentist }
        if lower.contains("eye") || lower.contains("vision") || lower.contains("optical") || lower.contains("ophthalmol") { return .optometrist }
        if lower.contains("therapy") || lower.contains("therapist") || lower.contains("physical therapy") { return .therapist }
        if lower.contains("clinic") || lower.contains("associates") || lower.contains("group") || lower.contains("practice") { return .clinic }
        return .doctor
    }
    
    // MARK: - Load All Data (for reload — uses @Published setters)
    
    private func loadAllData() {
        patients = load(key: StorageKeys.patients) ?? []
        insurancePolicies = load(key: StorageKeys.policies) ?? []
        insuranceCarriers = load(key: StorageKeys.carriers) ?? []
        paymentMethods = load(key: StorageKeys.payments) ?? []
        providers = load(key: StorageKeys.providers) ?? []
        visits = load(key: StorageKeys.visits) ?? []
        claims = load(key: StorageKeys.claims) ?? []
        scannedDocuments = load(key: StorageKeys.documents) ?? []
        
        // Merge common carriers
        for carrier in InsuranceCarrier.commonCarriers {
            if !insuranceCarriers.contains(where: { $0.name == carrier.name }) {
                insuranceCarriers.append(carrier)
            }
        }
        
        syncProvidersFromClaims()
    }
    
    /// Full async reload — use when data may have changed externally.
    func reloadAllData() async {
        isLoading = true
        await Task.yield()
        loadAllData()
        isLoading = false
    }
    
    // MARK: - Sync Providers from Claims
    
    /// Creates Provider entries from claims that have providerName but no matching Provider
    private func syncProvidersFromClaims() {
        var providersAdded = false
        
        for claim in claims {
            // Skip claims without provider name
            guard let providerName = claim.providerName, !providerName.isEmpty else {
                continue
            }
            
            // Check if provider already exists (by name, case-insensitive)
            let providerExists = providers.contains { provider in
                provider.name.lowercased() == providerName.lowercased()
            }
            
            if !providerExists {
                // Create a new provider from the claim data
                let newProvider = Provider(
                    name: providerName,
                    providerType: guessProviderType(from: providerName)
                )
                providers.append(newProvider)
                providersAdded = true
                
                // Update the claim with the new provider ID
                if let claimIndex = claims.firstIndex(where: { $0.id == claim.id }) {
                    claims[claimIndex].providerId = newProvider.id
                }
            } else if claim.providerId == nil {
                // Link existing provider to claim if not already linked
                if let existingProvider = providers.first(where: { $0.name.lowercased() == providerName.lowercased() }) {
                    if let claimIndex = claims.firstIndex(where: { $0.id == claim.id }) {
                        claims[claimIndex].providerId = existingProvider.id
                    }
                }
            }
        }
        
        if providersAdded {
            saveProviders()
            saveClaims()
        }
    }
    
    /// Guess provider type from name
    private func guessProviderType(from name: String) -> ProviderType {
        let lowercasedName = name.lowercased()
        
        if lowercasedName.contains("hospital") {
            return .hospital
        } else if lowercasedName.contains("pharmacy") || lowercasedName.contains("cvs") || lowercasedName.contains("walgreens") {
            return .pharmacy
        } else if lowercasedName.contains("urgent") {
            return .urgentCare
        } else if lowercasedName.contains("emergency") || lowercasedName.contains("er ") {
            return .emergencyRoom
        } else if lowercasedName.contains("lab") || lowercasedName.contains("laboratory") || lowercasedName.contains("quest") || lowercasedName.contains("labcorp") {
            return .laboratory
        } else if lowercasedName.contains("imaging") || lowercasedName.contains("radiology") || lowercasedName.contains("x-ray") || lowercasedName.contains("mri") {
            return .imagingCenter
        } else if lowercasedName.contains("dental") || lowercasedName.contains("dentist") {
            return .dentist
        } else if lowercasedName.contains("eye") || lowercasedName.contains("vision") || lowercasedName.contains("optical") || lowercasedName.contains("optom") {
            return .optometrist
        } else if lowercasedName.contains("clinic") || lowercasedName.contains("medical center") || lowercasedName.contains("health center") {
            return .clinic
        } else if lowercasedName.contains("dr.") || lowercasedName.contains("dr ") || lowercasedName.contains("md") || lowercasedName.contains("m.d.") {
            return .doctor
        } else if lowercasedName.contains("therapy") || lowercasedName.contains("therapist") || lowercasedName.contains("counseling") || lowercasedName.contains("psychology") {
            return .therapist
        } else {
            return .clinic // Default
        }
    }
    
    // MARK: - Generic Storage
    
    private func load<T: Codable>(key: String) -> [T]? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode([T].self, from: data)
    }
    
    private func save<T: Codable>(_ items: [T], key: String) {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
    
    // MARK: - Patient Operations
    
    func savePatient(_ patient: Patient) {
        var updatedPatient = patient
        updatedPatient.updatedAt = Date()
        
        if let index = patients.firstIndex(where: { $0.id == patient.id }) {
            patients[index] = updatedPatient
        } else {
            patients.append(updatedPatient)
        }
        savePatients()
        cloudPush(updatedPatient)
    }

    func deletePatient(_ patient: Patient) {
        patients.removeAll { $0.id == patient.id }
        // Also remove related data (capture ids first for the cloud cascade)
        let removedPolicyIds = insurancePolicies.filter { $0.patientId == patient.id }.map { $0.id }
        let removedVisitIds = visits.filter { $0.patientId == patient.id }.map { $0.id }
        let removedClaimIds = claims.filter { $0.patientId == patient.id }.map { $0.id }
        insurancePolicies.removeAll { $0.patientId == patient.id }
        visits.removeAll { $0.patientId == patient.id }
        claims.removeAll { $0.patientId == patient.id }

        savePatients()
        savePolicies()
        saveVisits()
        saveClaims()

        CloudKitSync.delete(recordName: Self.patientRecordPrefix + patient.id)
        removedClaimIds.forEach { CloudKitSync.delete(recordName: Self.claimRecordPrefix + $0) }
        removedPolicyIds.forEach { CloudKitSync.delete(recordName: Self.policyRecordPrefix + $0) }
        removedVisitIds.forEach { CloudKitSync.delete(recordName: Self.visitRecordPrefix + $0) }
    }
    
    private func savePatients() {
        save(patients, key: StorageKeys.patients)
    }
    
    func patients(for userId: String) -> [Patient] {
        // In a real app, filter by user ownership
        return patients
    }
    
    // MARK: - Insurance Policy Operations
    
    func savePolicy(_ policy: InsurancePolicy) {
        var updatedPolicy = policy
        updatedPolicy.updatedAt = Date()
        
        if let index = insurancePolicies.firstIndex(where: { $0.id == policy.id }) {
            insurancePolicies[index] = updatedPolicy
        } else {
            insurancePolicies.append(updatedPolicy)
        }
        savePolicies()
        cloudPush(updatedPolicy)
    }

    func deletePolicy(_ policy: InsurancePolicy) {
        insurancePolicies.removeAll { $0.id == policy.id }
        savePolicies()
        CloudKitSync.delete(recordName: Self.policyRecordPrefix + policy.id)
    }
    
    private func savePolicies() {
        save(insurancePolicies, key: StorageKeys.policies)
    }
    
    func policies(for patientId: String) -> [InsurancePolicy] {
        insurancePolicies.filter { $0.patientId == patientId }
    }
    
    // MARK: - Insurance Carrier Operations
    
    func saveCarrier(_ carrier: InsuranceCarrier) {
        var updatedCarrier = carrier
        updatedCarrier.updatedAt = Date()
        
        if let index = insuranceCarriers.firstIndex(where: { $0.id == carrier.id }) {
            insuranceCarriers[index] = updatedCarrier
        } else {
            insuranceCarriers.append(updatedCarrier)
        }
        saveCarriers()
        cloudPush(updatedCarrier)
    }

    func deleteCarrier(_ carrier: InsuranceCarrier) {
        insuranceCarriers.removeAll { $0.id == carrier.id }
        saveCarriers()
        CloudKitSync.delete(recordName: Self.carrierRecordPrefix + carrier.id)
    }
    
    private func saveCarriers() {
        save(insuranceCarriers, key: StorageKeys.carriers)
    }
    
    // MARK: - Payment Method Operations
    
    func savePaymentMethod(_ method: PaymentMethod) {
        var updatedMethod = method
        updatedMethod.updatedAt = Date()
        
        if let index = paymentMethods.firstIndex(where: { $0.id == method.id }) {
            paymentMethods[index] = updatedMethod
        } else {
            paymentMethods.append(updatedMethod)
        }
        savePaymentMethods()
        cloudPush(updatedMethod)
    }

    func deletePaymentMethod(_ method: PaymentMethod) {
        paymentMethods.removeAll { $0.id == method.id }
        savePaymentMethods()
        CloudKitSync.delete(recordName: Self.paymentRecordPrefix + method.id)
    }
    
    private func savePaymentMethods() {
        save(paymentMethods, key: StorageKeys.payments)
    }
    
    func paymentMethods(for patientId: String) -> [PaymentMethod] {
        paymentMethods.filter { $0.patientId == patientId }
    }
    
    // MARK: - Provider Operations
    
    func saveProvider(_ provider: Provider) {
        var updatedProvider = provider
        updatedProvider.updatedAt = Date()
        
        if let index = providers.firstIndex(where: { $0.id == provider.id }) {
            providers[index] = updatedProvider
        } else {
            providers.append(updatedProvider)
        }
        saveProviders()
        cloudPush(updatedProvider)
    }

    func deleteProvider(_ provider: Provider) {
        providers.removeAll { $0.id == provider.id }
        saveProviders()
        CloudKitSync.delete(recordName: Self.providerRecordPrefix + provider.id)
    }
    
    private func saveProviders() {
        save(providers, key: StorageKeys.providers)
    }
    
    // MARK: - Visit Operations
    
    func saveVisit(_ visit: Visit) {
        var updatedVisit = visit
        updatedVisit.updatedAt = Date()
        
        if let index = visits.firstIndex(where: { $0.id == visit.id }) {
            visits[index] = updatedVisit
        } else {
            visits.append(updatedVisit)
        }
        saveVisits()
        cloudPush(updatedVisit)
    }

    func deleteVisit(_ visit: Visit) {
        visits.removeAll { $0.id == visit.id }
        saveVisits()
        CloudKitSync.delete(recordName: Self.visitRecordPrefix + visit.id)
    }
    
    private func saveVisits() {
        save(visits, key: StorageKeys.visits)
    }
    
    func visits(for patientId: String) -> [Visit] {
        visits.filter { $0.patientId == patientId }
    }
    
    // MARK: - Claim Operations
    
    func saveClaim(_ claim: Claim) {
        var updatedClaim = claim
        updatedClaim.updatedAt = Date()
        
        if let index = claims.firstIndex(where: { $0.id == claim.id }) {
            claims[index] = updatedClaim
        } else {
            claims.append(updatedClaim)
            // Close the loop: a saved bill auto-completes matching follow-up tasks.
            FollowUpStore.shared.onBillSaved(
                providerName: updatedClaim.providerName,
                hasProcedureCodes: !(updatedClaim.procedureCodes?.isEmpty ?? true),
                hasDiagnosisCodes: !(updatedClaim.diagnosisCodes?.isEmpty ?? true))
        }
        saveClaims()
        cloudPush(updatedClaim)
    }

    func deleteClaim(_ claim: Claim) {
        claims.removeAll { $0.id == claim.id }
        saveClaims()
        CloudKitSync.delete(recordName: PatientDataService.claimRecordPrefix + claim.id)
    }
    
    private func saveClaims() {
        save(claims, key: StorageKeys.claims)
    }
    
    func claims(for patientId: String) -> [Claim] {
        claims.filter { $0.patientId == patientId }
    }
    
    // MARK: - Scanned Document Operations
    
    func saveDocument(_ document: ScannedDocument) {
        var updatedDocument = document
        updatedDocument.updatedAt = Date()
        
        if let index = scannedDocuments.firstIndex(where: { $0.id == document.id }) {
            scannedDocuments[index] = updatedDocument
        } else {
            scannedDocuments.append(updatedDocument)
        }
        saveDocuments()
        cloudPush(updatedDocument)
    }

    func deleteDocument(_ document: ScannedDocument) {
        scannedDocuments.removeAll { $0.id == document.id }
        saveDocuments()
        CloudKitSync.delete(recordName: Self.documentRecordPrefix + document.id)
    }
    
    private func saveDocuments() {
        save(scannedDocuments, key: StorageKeys.documents)
    }
    
    func documents(for patientId: String) -> [ScannedDocument] {
        scannedDocuments.filter { $0.patientId == patientId }
    }
    
    // MARK: - Duplicate Detection
    
    /// Find an existing claim that matches the given criteria.
    /// Match priority: (1) same account/claim number, (2) same provider + same service date,
    /// (3) same provider + service date within 7 days + similar amount.
    func findDuplicateClaim(
        patientId: String,
        providerName: String?,
        claimNumber: String?,
        serviceDate: Date,
        billedAmount: Double
    ) -> Claim? {
        let patientClaims = claims(for: patientId)
        
        // Priority 1: Exact account/claim number match
        if let number = claimNumber, !number.isEmpty {
            if let match = patientClaims.first(where: {
                $0.claimNumber?.lowercased() == number.lowercased()
            }) {
                return match
            }
        }
        
        // Priority 2: Same provider + exact service date
        if let name = providerName, !name.isEmpty {
            let nameLower = name.lowercased()
            if let match = patientClaims.first(where: {
                $0.providerName?.lowercased() == nameLower
                && Calendar.current.isDate($0.serviceDate, inSameDayAs: serviceDate)
            }) {
                return match
            }
            
            // Priority 3: Same provider + within 7 days + amount within 20%
            let sevenDays: TimeInterval = 7 * 24 * 60 * 60
            if let match = patientClaims.first(where: {
                guard $0.providerName?.lowercased() == nameLower else { return false }
                let dayDiff = abs($0.serviceDate.timeIntervalSince(serviceDate))
                guard dayDiff <= sevenDays else { return false }
                // Amount similarity: within 20% or within $5
                let amtDiff = abs($0.billedAmount - billedAmount)
                let threshold = max(billedAmount * 0.2, 5.0)
                return amtDiff <= threshold
            }) {
                return match
            }
        }
        
        return nil
    }
    
    // MARK: - Summary Data
    
    func totalOutstandingBalance(for patientId: String) -> Double {
        claims(for: patientId)
            .filter { $0.status != .paid && $0.status != .closed }
            .reduce(0) { $0 + ($1.patientResponsibility ?? 0) }
    }
    
    func totalBills(for patientId: String) -> Int {
        claims(for: patientId).count
    }
    
    func pendingClaims(for patientId: String) -> [Claim] {
        claims(for: patientId).filter { $0.isPending }
    }
    
    func recentVisits(for patientId: String, limit: Int = 5) -> [Visit] {
        Array(visits(for: patientId)
            .sorted { $0.visitDate > $1.visitDate }
            .prefix(limit))
    }
    
    // MARK: - Reset (for debugging)
    
    func clearCache() {
        isLoading = true
        // Clear in-memory data but keep storage
        patients = []
        insurancePolicies = []
        paymentMethods = []
        providers = []
        visits = []
        claims = []
        scannedDocuments = []
        // Reload from storage
        loadAllData()
        isLoading = false
    }
    
    func resetAllData() {
        isLoading = true
        patients = []
        insurancePolicies = []
        insuranceCarriers = []
        paymentMethods = []
        providers = []
        visits = []
        claims = []
        scannedDocuments = []
        
        UserDefaults.standard.removeObject(forKey: StorageKeys.patients)
        UserDefaults.standard.removeObject(forKey: StorageKeys.policies)
        UserDefaults.standard.removeObject(forKey: StorageKeys.carriers)
        UserDefaults.standard.removeObject(forKey: StorageKeys.payments)
        UserDefaults.standard.removeObject(forKey: StorageKeys.providers)
        UserDefaults.standard.removeObject(forKey: StorageKeys.visits)
        UserDefaults.standard.removeObject(forKey: StorageKeys.claims)
        UserDefaults.standard.removeObject(forKey: StorageKeys.documents)
        
        // Also wipe synced records so the next cloud refresh doesn't restore them.
        for type in [Self.patientRecordType, Self.claimRecordType, Self.policyRecordType,
                     Self.carrierRecordType, Self.paymentRecordType, Self.providerRecordType,
                     Self.visitRecordType, Self.documentRecordType] {
            CloudKitSync.deleteAll(recordType: type)
        }

        // Reload common carriers
        for carrier in InsuranceCarrier.commonCarriers {
            if !insuranceCarriers.contains(where: { $0.name == carrier.name }) {
                insuranceCarriers.append(carrier)
            }
        }
        isLoading = false
    }

    // MARK: - CloudKit sync (all collections, private database)
    //
    // Every collection syncs through the user's *private* iCloud database as
    // JSON-blob records (the models are Codable), with last-write-wins by their
    // `updatedAt`. Best-effort: no-ops cleanly without an iCloud account, so the
    // app always works from its UserDefaults cache.
    //
    // NOTE: each record type below needs `recordName` marked Queryable in the
    // CloudKit Dashboard for the pull to return records.

    static let patientRecordType  = "Patient";       static let patientRecordPrefix  = "patient_"
    static let claimRecordType    = "Claim";         static let claimRecordPrefix    = "claim_"
    static let policyRecordType   = "InsurancePolicy"; static let policyRecordPrefix = "policy_"
    static let carrierRecordType  = "InsuranceCarrier"; static let carrierRecordPrefix = "carrier_"
    static let paymentRecordType  = "PaymentMethod";  static let paymentRecordPrefix  = "payment_"
    static let providerRecordType = "Provider";      static let providerRecordPrefix = "provider_"
    static let visitRecordType    = "Visit";         static let visitRecordPrefix    = "visit_"
    static let documentRecordType = "ScannedDocument"; static let documentRecordPrefix = "document_"

    /// Pull every collection from iCloud and merge into local. Safe anytime.
    func refreshFromCloud() {
        Task { await syncFromCloud() }
    }

    private func cloudPush<T: Encodable & Identifiable>(_ item: T, updatedAt: Date,
                                                        prefix: String, recordType: String) where T.ID == String {
        if let r = CloudKitSync.blobRecord(item, recordName: prefix + item.id,
                                           updatedAt: updatedAt, recordType: recordType) {
            CloudKitSync.save(r)
        }
    }

    private func cloudPush(_ x: Patient)          { cloudPush(x, updatedAt: x.updatedAt, prefix: Self.patientRecordPrefix,  recordType: Self.patientRecordType) }
    private func cloudPush(_ x: Claim)            { cloudPush(x, updatedAt: x.updatedAt, prefix: Self.claimRecordPrefix,    recordType: Self.claimRecordType) }
    private func cloudPush(_ x: InsurancePolicy)  { cloudPush(x, updatedAt: x.updatedAt, prefix: Self.policyRecordPrefix,   recordType: Self.policyRecordType) }
    private func cloudPush(_ x: InsuranceCarrier) { cloudPush(x, updatedAt: x.updatedAt, prefix: Self.carrierRecordPrefix,  recordType: Self.carrierRecordType) }
    private func cloudPush(_ x: PaymentMethod)    { cloudPush(x, updatedAt: x.updatedAt, prefix: Self.paymentRecordPrefix,  recordType: Self.paymentRecordType) }
    private func cloudPush(_ x: Provider)         { cloudPush(x, updatedAt: x.updatedAt, prefix: Self.providerRecordPrefix, recordType: Self.providerRecordType) }
    private func cloudPush(_ x: Visit)            { cloudPush(x, updatedAt: x.updatedAt, prefix: Self.visitRecordPrefix,    recordType: Self.visitRecordType) }
    private func cloudPush(_ x: ScannedDocument)  { cloudPush(x, updatedAt: x.updatedAt, prefix: Self.documentRecordPrefix, recordType: Self.documentRecordType) }

    private func syncFromCloud() async {
        guard await CloudKitSync.accountAvailable() else { return }

        async let rPatients: [Patient]           = CloudKitSync.pullBlobs(Patient.self,          recordType: Self.patientRecordType)
        async let rClaims: [Claim]               = CloudKitSync.pullBlobs(Claim.self,            recordType: Self.claimRecordType)
        async let rPolicies: [InsurancePolicy]   = CloudKitSync.pullBlobs(InsurancePolicy.self,  recordType: Self.policyRecordType)
        async let rCarriers: [InsuranceCarrier]  = CloudKitSync.pullBlobs(InsuranceCarrier.self, recordType: Self.carrierRecordType)
        async let rPayments: [PaymentMethod]     = CloudKitSync.pullBlobs(PaymentMethod.self,    recordType: Self.paymentRecordType)
        async let rProviders: [Provider]         = CloudKitSync.pullBlobs(Provider.self,         recordType: Self.providerRecordType)
        async let rVisits: [Visit]               = CloudKitSync.pullBlobs(Visit.self,            recordType: Self.visitRecordType)
        async let rDocuments: [ScannedDocument]  = CloudKitSync.pullBlobs(ScannedDocument.self,  recordType: Self.documentRecordType)

        let (remPatients, remClaims, remPolicies, remCarriers, remPayments, remProviders, remVisits, remDocuments)
            = await (rPatients, rClaims, rPolicies, rCarriers, rPayments, rProviders, rVisits, rDocuments)

        patients          = Self.merge(local: patients,          remote: remPatients,  updatedAt: \.updatedAt, push: { [weak self] in self?.cloudPush($0) })
        claims            = Self.merge(local: claims,            remote: remClaims,    updatedAt: \.updatedAt, push: { [weak self] in self?.cloudPush($0) })
        insurancePolicies = Self.merge(local: insurancePolicies, remote: remPolicies,  updatedAt: \.updatedAt, push: { [weak self] in self?.cloudPush($0) })
        insuranceCarriers = Self.merge(local: insuranceCarriers, remote: remCarriers,  updatedAt: \.updatedAt, push: { [weak self] in self?.cloudPush($0) })
        paymentMethods    = Self.merge(local: paymentMethods,    remote: remPayments,  updatedAt: \.updatedAt, push: { [weak self] in self?.cloudPush($0) })
        providers         = Self.merge(local: providers,         remote: remProviders, updatedAt: \.updatedAt, push: { [weak self] in self?.cloudPush($0) })
        visits            = Self.merge(local: visits,            remote: remVisits,    updatedAt: \.updatedAt, push: { [weak self] in self?.cloudPush($0) })
        scannedDocuments  = Self.merge(local: scannedDocuments,  remote: remDocuments, updatedAt: \.updatedAt, push: { [weak self] in self?.cloudPush($0) })

        savePatients(); saveClaims(); savePolicies(); saveCarriers()
        savePaymentMethods(); saveProviders(); saveVisits(); saveDocuments()
    }

    /// Last-write-wins merge: remote wins when newer, local wins (and is pushed)
    /// when newer, remote-only items are added, local-only items are pushed up.
    private static func merge<T: Identifiable>(local: [T], remote: [T],
                                               updatedAt: (T) -> Date,
                                               push: (T) -> Void) -> [T] where T.ID == String {
        var byId = Dictionary(local.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let remoteIds = Set(remote.map { $0.id })
        for r in remote {
            if let l = byId[r.id] {
                if updatedAt(l) > updatedAt(r) { push(l) }   // local newer → keep & push
                else { byId[r.id] = r }                      // remote newer/equal → take remote
            } else {
                byId[r.id] = r                               // new from another device
            }
        }
        for l in local where !remoteIds.contains(l.id) { push(l) }   // offline-created
        return Array(byId.values)
    }
}

// MARK: - Shared CloudKit helper (private database)

/// Thin best-effort wrapper over the user's private CloudKit database, shared by
/// the follow-up task sync and the patient/claim sync.
enum CloudKitSync {
    static let containerID = "iCloud.com.billguard.BillGuard"
    static var container: CKContainer { CKContainer(identifier: containerID) }
    static var database: CKDatabase { container.privateCloudDatabase }

    static func accountAvailable() async -> Bool {
        (try? await container.accountStatus()) == .available
    }

    /// Force-overwrite save (last-write-wins): `.allKeys` ignores the server
    /// change-tag so a freshly-built record updates an existing one instead of
    /// failing with a conflict. Fire-and-forget.
    static func save(_ record: CKRecord) {
        let op = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
        op.savePolicy = .allKeys
        op.qualityOfService = .utility
        database.add(op)
    }

    static func delete(recordName: String) {
        let op = CKModifyRecordsOperation(recordsToSave: nil,
                                          recordIDsToDelete: [CKRecord.ID(recordName: recordName)])
        op.qualityOfService = .utility
        database.add(op)
    }

    /// Delete every record of a type (best-effort; used by reset-all).
    static func deleteAll(recordType: String) {
        Task {
            guard await accountAvailable() else { return }
            do {
                let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
                let (results, _) = try await database.records(matching: query)
                let ids = results.compactMap { id, result -> CKRecord.ID? in
                    if case .success = result { return id }
                    return nil
                }
                guard !ids.isEmpty else { return }
                let op = CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: ids)
                op.qualityOfService = .utility
                database.add(op)
            } catch { }
        }
    }

    /// Pull & decode JSON-blob records. Empty when iCloud is unavailable or the
    /// record type doesn't exist yet.
    static func pullBlobs<T: Decodable>(_ type: T.Type, recordType: String) async -> [T] {
        do {
            let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
            let (results, _) = try await database.records(matching: query)
            return results.compactMap { _, result -> T? in
                guard case .success(let record) = result,
                      let data = record["payload"] as? Data else { return nil }
                return try? JSONDecoder().decode(T.self, from: data)
            }
        } catch { return [] }
    }

    /// Build a JSON-blob record: the whole Codable value under `payload`, plus
    /// `updatedAt` for conflict resolution.
    static func blobRecord<T: Encodable>(_ item: T, recordName: String, updatedAt: Date,
                                         recordType: String) -> CKRecord? {
        guard let data = try? JSONEncoder().encode(item) else { return nil }
        let record = CKRecord(recordType: recordType, recordID: CKRecord.ID(recordName: recordName))
        record["payload"] = data
        record["updatedAt"] = updatedAt
        return record
    }
}
