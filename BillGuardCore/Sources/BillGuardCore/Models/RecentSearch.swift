//
//  RecentSearch.swift
//  BillGuard
//
//  Model for tracking recent searches
//

import Foundation

public struct RecentSearch: Identifiable, Codable, Hashable {
    public let id: String
    public let query: String
    public let resultCode: String?
    public let resultDescription: String?
    public let timestamp: Date
    
    public init(id: String = UUID().uuidString,
         query: String,
         resultCode: String? = nil,
         resultDescription: String? = nil,
         timestamp: Date = Date()) {
        self.id = id
        self.query = query
        self.resultCode = resultCode
        self.resultDescription = resultDescription
        self.timestamp = timestamp
    }
    
    public var displayText: String {
        if let code = resultCode, let description = resultDescription {
            return "\(code) – \(description)"
        }
        return query
    }
}

// MARK: - Recent Search Manager

public class RecentSearchManager: ObservableObject {
    
    @Published public var recentSearches: [RecentSearch] = []
    
    private let maxRecentSearches = 10
    private let storageKey = "recentSearches"
    
    public init() {
        loadRecentSearches()
    }
    
    public func addSearch(_ search: RecentSearch) {
        // Remove duplicate if exists
        recentSearches.removeAll { $0.query.lowercased() == search.query.lowercased() }
        
        // Add to beginning
        recentSearches.insert(search, at: 0)
        
        // Trim to max
        if recentSearches.count > maxRecentSearches {
            recentSearches = Array(recentSearches.prefix(maxRecentSearches))
        }
        
        saveRecentSearches()
    }
    
    public func addSearch(query: String, code: MedicalCode? = nil) {
        let search = RecentSearch(
            query: query,
            resultCode: code?.code,
            resultDescription: code?.shortDescription
        )
        addSearch(search)
    }
    
    public func clearAll() {
        recentSearches.removeAll()
        saveRecentSearches()
    }
    
    public func removeSearch(_ search: RecentSearch) {
        recentSearches.removeAll { $0.id == search.id }
        saveRecentSearches()
    }
    
    private func loadRecentSearches() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }
        
        do {
            recentSearches = try JSONDecoder().decode([RecentSearch].self, from: data)
        } catch {
            print("Failed to load recent searches: \(error)")
        }
    }
    
    private func saveRecentSearches() {
        do {
            let data = try JSONEncoder().encode(recentSearches)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            print("Failed to save recent searches: \(error)")
        }
    }
}
