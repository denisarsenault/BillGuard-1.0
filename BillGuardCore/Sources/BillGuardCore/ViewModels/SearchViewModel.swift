//
//  SearchViewModel.swift
//  BillGuard
//
//  ViewModel for search functionality
//

import Foundation
import Combine

@MainActor
class SearchViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var searchText = ""
    @Published var searchResults: [MedicalCode] = []
    @Published var isSearching = false
    @Published var hasSearched = false
    @Published var errorMessage: String?
    @Published var selectedCodeType: MedicalCodeType?
    
    @Published var popularCodes: [MedicalCode] = []
    @Published var isLoadingPopular = false
    
    // MARK: - Dependencies
    
    let cloudKitService: CloudKitService
    let recentSearchManager = RecentSearchManager()
    
    // MARK: - Private Properties
    
    private var searchTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    init(cloudKitService: CloudKitService) {
        self.cloudKitService = cloudKitService
        setupSearchDebounce()
        
        // Load popular codes immediately at init
        loadPopularCodes()
        // NOTE: Do NOT load popular codes here — @Published mutations during
        // AppState.init() deadlock SwiftUI. HomeView.onAppear handles it.
    }
    
    // MARK: - Search Methods
    
    private func setupSearchDebounce() {
        $searchText
            .dropFirst() // Skip initial empty value during init
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] query in
                guard let self = self else { return }
                Task {
                    await self.performSearch(query: query)
                }
            }
            .store(in: &cancellables)
    }
    
    func performSearch(query: String) async {
        // Cancel any existing search
        searchTask?.cancel()
        
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        
        print("🔍 performSearch: query='\(trimmedQuery)', isAvailable=\(cloudKitService.isAvailable)")
        
        guard !trimmedQuery.isEmpty else {
            searchResults = []
            hasSearched = false
            errorMessage = nil
            return
        }
        
        isSearching = true
        hasSearched = true
        errorMessage = nil
        
        searchTask = Task {
            // Always use offline search since CloudKit isn't set up
            let results = cloudKitService.searchCodesOffline(
                query: trimmedQuery,
                codeType: selectedCodeType
            )
            
            print("🔍 performSearch: got \(results.count) results")
            
            if !Task.isCancelled {
                searchResults = results
                if results.isEmpty {
                    errorMessage = "No codes found matching '\(trimmedQuery)'"
                }
            }
            
            if !Task.isCancelled {
                isSearching = false
            }
        }
    }
    
    func search() async {
        await performSearch(query: searchText)
    }
    
    func clearSearch() {
        searchText = ""
        searchResults = []
        hasSearched = false
        errorMessage = nil
        searchTask?.cancel()
    }
    
    // MARK: - Recent Searches
    
    func recordSearch(code: MedicalCode) {
        recentSearchManager.addSearch(query: code.code, code: code)
    }
    
    func recordSearch(query: String) {
        recentSearchManager.addSearch(query: query)
    }
    
    // MARK: - Popular Codes
    
    func loadPopularCodes() {
        isLoadingPopular = true
        
        let allCodes = cloudKitService.allCodes
        #if DEBUG
        print("📋 [Popular] allCodes count: \(allCodes.count)")
        #endif
        
        if allCodes.isEmpty {
            // JSON didn't load yet — use hardcoded defaults and schedule retry
            let fallback = MedicalCode.sampleCodes
            #if DEBUG
            print("📋 [Popular] Fallback sampleCodes count: \(fallback.count)")
            #endif
            if !fallback.isEmpty {
                popularCodes = Array(fallback.prefix(8))
            } else {
                // Even sampleCodes empty — retry after delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                    self?.loadPopularCodes()
                }
            }
            isLoadingPopular = false
            return
        }
        
        let popularCodeValues = ["99213", "99214", "99212", "99211", "70450", "93000", "J06.9", "M54.5"]
        
        var found: [MedicalCode] = []
        for codeValue in popularCodeValues {
            if let code = cloudKitService.lookupCode(codeValue) {
                found.append(code)
            }
        }
        
        #if DEBUG
        print("📋 [Popular] Matched \(found.count)/\(popularCodeValues.count) codes by lookup")
        #endif
        
        if !found.isEmpty {
            popularCodes = found
        } else {
            // Lookup failed — just take first 8 codes
            popularCodes = Array(allCodes.prefix(8))
            #if DEBUG
            print("📋 [Popular] Using first 8 from allCodes")
            #endif
        }
        
        isLoadingPopular = false
    }
    
    // MARK: - Filter by Code Type
    
    func setCodeTypeFilter(_ type: MedicalCodeType?) {
        selectedCodeType = type
        
        if !searchText.isEmpty {
            Task {
                await performSearch(query: searchText)
            }
        }
    }
    
    // MARK: - Auto-Suggest
    
    var suggestions: [MedicalCode] {
        guard searchText.count >= 2 else { return [] }
        return Array(searchResults.prefix(5))
    }
}
