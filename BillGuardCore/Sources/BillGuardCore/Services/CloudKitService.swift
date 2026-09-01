//
//  CloudKitService.swift
//  BillGuard
//
//  Service for all CloudKit operations
//

import Foundation
import CloudKit
import Combine

// MARK: - CloudKit Configuration

struct CloudKitConfig {
    // Update this with your actual container identifier
    static let containerIdentifier = "iCloud.com.billguard.BillGuard"
    
    // Use public database for shared medical code data
    static let databaseScope: CKDatabase.Scope = .public
}

// MARK: - CloudKit Error

enum CloudKitError: Error, LocalizedError {
    case notAuthenticated
    case networkUnavailable
    case quotaExceeded
    case recordNotFound
    case invalidRecord
    case serverError(String)
    case unknown(Error)
    
    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Please sign in to iCloud in Settings to use this feature."
        case .networkUnavailable:
            return "No internet connection. Please check your network and try again."
        case .quotaExceeded:
            return "Storage limit reached. Please try again later."
        case .recordNotFound:
            return "The requested code was not found."
        case .invalidRecord:
            return "Invalid data received from server."
        case .serverError(let message):
            return "Server error: \(message)"
        case .unknown(let error):
            return error.localizedDescription
        }
    }
    
    static func from(_ error: Error) -> CloudKitError {
        guard let ckError = error as? CKError else {
            return .unknown(error)
        }
        
        switch ckError.code {
        case .notAuthenticated:
            return .notAuthenticated
        case .networkUnavailable, .networkFailure:
            return .networkUnavailable
        case .quotaExceeded:
            return .quotaExceeded
        case .unknownItem:
            return .recordNotFound
        default:
            return .serverError(ckError.localizedDescription)
        }
    }
}

// MARK: - CloudKit Service

@MainActor
class CloudKitService: ObservableObject {
    
    // MARK: - Properties
    
    /// CloudKit container — created lazily on first use to avoid blocking launch
    private var _container: CKContainer?
    var container: CKContainer {
        if _container == nil {
            _container = CKContainer(identifier: CloudKitConfig.containerIdentifier)
        }
        return _container!
    }
    var database: CKDatabase {
        container.database(with: CloudKitConfig.databaseScope)
    }
    
    @Published var isAvailable = false
    @Published var accountStatus: CKAccountStatus = .couldNotDetermine
    
    /// All loaded medical codes (from JSON or CloudKit)
    private var _allCodes: [MedicalCode]?
    var allCodes: [MedicalCode] {
        if _allCodes == nil { loadLocalData() }
        return _allCodes!
    }
    
    /// O(1) lookup by code string (e.g. "99213" → MedicalCode)
    private var _codeLookup: [String: MedicalCode]?
    var codeLookup: [String: MedicalCode] {
        if _codeLookup == nil { loadLocalData() }
        return _codeLookup!
    }
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    init() {
        // Nothing heavy here — codes load lazily on first access
    }
    
    // MARK: - Load Local Data
    
    private func loadLocalData() {
        guard _allCodes == nil else { return }
        let codes = MedicalCode.sampleCodes
        _allCodes = codes
        _codeLookup = Dictionary(codes.map { ($0.code.uppercased(), $0) }, uniquingKeysWith: { first, _ in first })
    }
    
    // MARK: - Account Status
    
    func checkAccountStatus() async {
        // 3-second timeout — don't let iCloud hang the app
        let statusTask = Task { () -> CKAccountStatus in
            try await container.accountStatus()
        }
        
        let timeoutTask = Task {
            try await Task.sleep(nanoseconds: 3_000_000_000)
            statusTask.cancel()
        }
        
        do {
            let status = try await statusTask.value
            timeoutTask.cancel()
            await MainActor.run {
                accountStatus = status
                isAvailable = (status == .available)
            }
            if status != .available {
                print("⚠️ iCloud account not available: \(status.rawValue)")
            }
        } catch {
            timeoutTask.cancel()
            print("⚠️ iCloud check skipped (timeout or error): \(error.localizedDescription)")
            await MainActor.run {
                isAvailable = false
            }
        }
    }
    
    // MARK: - Search Medical Codes
    
    func searchCodes(query: String, codeType: MedicalCodeType? = nil) async throws -> [MedicalCode] {
        guard !query.isEmpty else { return [] }
        
        // Always use local search first (faster and works offline)
        let results = searchCodesOffline(query: query, codeType: codeType)
        return results
    }
    
    // MARK: - Fetch Single Code
    
    func fetchCode(byID id: String) async throws -> MedicalCode {
        // First check local data
        if let code = allCodes.first(where: { $0.id == id }) {
            return code
        }
        
        // If CloudKit available, try remote
        if isAvailable {
            let recordID = CKRecord.ID(recordName: id)
            
            do {
                let record = try await database.record(for: recordID)
                
                guard let code = MedicalCode(from: record) else {
                    throw CloudKitError.invalidRecord
                }
                
                return code
            } catch {
                throw CloudKitError.from(error)
            }
        }
        
        throw CloudKitError.recordNotFound
    }
    
    func fetchCode(byCode code: String) async throws -> MedicalCode? {
        // O(1) dictionary lookup first
        if let localCode = codeLookup[code.uppercased()] {
            return localCode
        }
        
        // Try CloudKit if available
        if isAvailable {
            let predicate = NSPredicate(format: "code == %@", code)
            let results = try await queryRecords(predicate: predicate, limit: 1)
            return results.first
        }
        
        return nil
    }
    
    // MARK: - Fetch Popular Codes
    
    func fetchPopularCodes() async throws -> [MedicalCode] {
        // Return popular codes from local data
        let popularCodeValues = ["99213", "99214", "99212", "70450", "93000", "87811", "J06.9", "M54.5", "73610"]
        
        return allCodes.filter { code in
            popularCodeValues.contains(code.code)
        }.sorted { code1, code2 in
            guard let idx1 = popularCodeValues.firstIndex(of: code1.code),
                  let idx2 = popularCodeValues.firstIndex(of: code2.code) else {
                return false
            }
            return idx1 < idx2
        }
    }
    
    // MARK: - Fetch by Category
    
    func fetchCodes(byCategory category: String) async throws -> [MedicalCode] {
        return allCodes.filter { $0.category.lowercased() == category.lowercased() }
    }
    
    // MARK: - Fetch Related Codes
    
    func fetchRelatedCodes(for code: MedicalCode) async throws -> [MedicalCode] {
        guard !code.relatedCodes.isEmpty else { return [] }
        // O(n) where n = relatedCodes count, not allCodes count
        return code.relatedCodes.compactMap { codeLookup[$0.uppercased()] }
    }
    
    // MARK: - Fast Code Lookup (O(1))
    
    /// Look up a single code by exact code string. O(1) dictionary lookup.
    /// Use this instead of searchCodesOffline when you know the exact code.
    func lookupCode(_ codeString: String) -> MedicalCode? {
        codeLookup[codeString.uppercased()]
    }
    
    /// Batch lookup: returns a dictionary of found codes. O(n) where n = input count.
    func lookupCodes(_ codeStrings: [String]) -> [String: MedicalCode] {
        var result: [String: MedicalCode] = [:]
        for code in codeStrings {
            if let found = codeLookup[code.uppercased()] {
                result[code] = found
            }
        }
        return result
    }
    
    // MARK: - Private Query Method (CloudKit)
    
    private func queryRecords(predicate: NSPredicate, limit: Int = 50) async throws -> [MedicalCode] {
        let query = CKQuery(recordType: MedicalCode.recordType, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "code", ascending: true)]
        
        var allRecords: [CKRecord] = []
        
        do {
            let (records, _) = try await database.records(matching: query, resultsLimit: limit)
            
            for (_, result) in records {
                switch result {
                case .success(let record):
                    allRecords.append(record)
                case .failure(let error):
                    print("⚠️ Failed to fetch record: \(error)")
                }
            }
        } catch {
            throw CloudKitError.from(error)
        }
        
        return allRecords.compactMap { MedicalCode(from: $0) }
    }
    
    // MARK: - Offline Search (Using Local Data)
    
    func searchCodesOffline(query: String, codeType: MedicalCodeType? = nil) -> [MedicalCode] {
        let normalizedQuery = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return [] }
        
        // Fast path: if query looks like an exact code, try dictionary first
        if let exact = codeLookup[query.uppercased()] {
            if codeType == nil || exact.codeType == codeType {
                return [exact]
            }
        }
        
        var results = allCodes.filter { code in
            // Filter by code type if specified
            if let type = codeType, code.codeType != type {
                return false
            }
            
            // Search in code (exact or prefix match - highest priority)
            if code.code.lowercased().hasPrefix(normalizedQuery) {
                return true
            }
            
            // Search in code (contains)
            if code.code.lowercased().contains(normalizedQuery) {
                return true
            }
            
            // Search in short description
            if code.shortDescription.lowercased().contains(normalizedQuery) {
                return true
            }
            
            // Search in plain English description
            if code.plainEnglishDescription.lowercased().contains(normalizedQuery) {
                return true
            }
            
            // Search in keywords
            if code.keywords.contains(where: { $0.lowercased().contains(normalizedQuery) }) {
                return true
            }
            
            // Search in category
            if code.category.lowercased().contains(normalizedQuery) {
                return true
            }
            
            // Search in common uses
            if code.commonUses.contains(where: { $0.lowercased().contains(normalizedQuery) }) {
                return true
            }
            
            return false
        }
        
        // Sort results: exact code matches first, then prefix matches, then others
        results.sort { code1, code2 in
            let code1Lower = code1.code.lowercased()
            let code2Lower = code2.code.lowercased()
            
            // Exact match first
            if code1Lower == normalizedQuery && code2Lower != normalizedQuery {
                return true
            }
            if code2Lower == normalizedQuery && code1Lower != normalizedQuery {
                return false
            }
            
            // Then prefix match
            if code1Lower.hasPrefix(normalizedQuery) && !code2Lower.hasPrefix(normalizedQuery) {
                return true
            }
            if code2Lower.hasPrefix(normalizedQuery) && !code1Lower.hasPrefix(normalizedQuery) {
                return false
            }
            
            // Then alphabetical
            return code1Lower < code2Lower
        }
        
        return results
    }
    
    // MARK: - Get All Codes by Type
    
    func getAllCodes(ofType type: MedicalCodeType? = nil) -> [MedicalCode] {
        if let type = type {
            return allCodes.filter { $0.codeType == type }
        }
        return allCodes
    }
}

// MARK: - CloudKit Subscription (for future real-time updates)

extension CloudKitService {
    
    func setupSubscriptions() async {
        // Create subscription for code updates
        let subscription = CKQuerySubscription(
            recordType: MedicalCode.recordType,
            predicate: NSPredicate(value: true),
            subscriptionID: "code-updates",
            options: [.firesOnRecordCreation, .firesOnRecordUpdate]
        )
        
        let notification = CKSubscription.NotificationInfo()
        notification.shouldSendContentAvailable = true
        subscription.notificationInfo = notification
        
        do {
            try await database.save(subscription)
            print("✅ CloudKit subscription created")
        } catch {
            print("⚠️ Failed to create subscription: \(error)")
        }
    }
}
