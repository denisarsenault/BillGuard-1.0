//
//  PatientDataService.swift
//  BillGuard
//
//  Service for managing patient-related data with local storage
//

import Foundation
import Combine

@MainActor
public final class PatientDataService: ObservableObject {
    public static let shared = PatientDataService()
    
    // MARK: - Published Data
    @Published public var patients: [Patient]
    @Published var insurancePolicies: [InsurancePolicy]
    @Published var insuranceCarriers: [InsuranceCarrier]
    @Published var paymentMethods: [PaymentMethod]
    @Published var providers: [Provider]
    @Published var visits: [Visit]
    @Published public var claims: [Claim]
    @Published var scannedDocuments: [ScannedDocument]
    
    @Published public var isLoading = false
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
    }
    
    func deletePatient(_ patient: Patient) {
        patients.removeAll { $0.id == patient.id }
        // Also remove related data
        insurancePolicies.removeAll { $0.patientId == patient.id }
        visits.removeAll { $0.patientId == patient.id }
        claims.removeAll { $0.patientId == patient.id }
        
        savePatients()
        savePolicies()
        saveVisits()
        saveClaims()
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
    }
    
    func deletePolicy(_ policy: InsurancePolicy) {
        insurancePolicies.removeAll { $0.id == policy.id }
        savePolicies()
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
    }
    
    func deleteCarrier(_ carrier: InsuranceCarrier) {
        insuranceCarriers.removeAll { $0.id == carrier.id }
        saveCarriers()
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
    }
    
    func deletePaymentMethod(_ method: PaymentMethod) {
        paymentMethods.removeAll { $0.id == method.id }
        savePaymentMethods()
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
    }
    
    func deleteProvider(_ provider: Provider) {
        providers.removeAll { $0.id == provider.id }
        saveProviders()
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
    }
    
    func deleteVisit(_ visit: Visit) {
        visits.removeAll { $0.id == visit.id }
        saveVisits()
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
        }
        saveClaims()
    }
    
    func deleteClaim(_ claim: Claim) {
        claims.removeAll { $0.id == claim.id }
        saveClaims()
    }
    
    private func saveClaims() {
        save(claims, key: StorageKeys.claims)
    }
    
    public func claims(for patientId: String) -> [Claim] {
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
    }
    
    func deleteDocument(_ document: ScannedDocument) {
        scannedDocuments.removeAll { $0.id == document.id }
        saveDocuments()
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
        
        // Reload common carriers
        for carrier in InsuranceCarrier.commonCarriers {
            if !insuranceCarriers.contains(where: { $0.name == carrier.name }) {
                insuranceCarriers.append(carrier)
            }
        }
        isLoading = false
    }
}
