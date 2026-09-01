//
//  FavoritesManager.swift
//  BillGuard
//
//  Manages saved/favorite medical codes (local storage)
//

import Foundation
import Combine

class FavoritesManager: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var favorites: [MedicalCode]
    @Published var favoriteIDs: Set<String>
    
    // MARK: - Private Properties
    
    private let storageKey = "savedFavorites"
    private let idStorageKey = "favoriteIDs"
    
    // MARK: - Initialization
    
    init() {
        // Load into locals first — no @Published triggers
        var loadedFavorites: [MedicalCode] = []
        if let data = UserDefaults.standard.data(forKey: storageKey) {
            loadedFavorites = (try? JSONDecoder().decode([MedicalCode].self, from: data)) ?? []
        }
        _favorites = Published(initialValue: loadedFavorites)
        _favoriteIDs = Published(initialValue: Set(loadedFavorites.map { $0.id }))
    }
    
    // MARK: - Public Methods
    
    /// Check if a code is in favorites
    func isFavorite(_ code: MedicalCode) -> Bool {
        return favoriteIDs.contains(code.id)
    }
    
    func isFavorite(id: String) -> Bool {
        return favoriteIDs.contains(id)
    }
    
    /// Add a code to favorites
    func addFavorite(_ code: MedicalCode) {
        guard !isFavorite(code) else { return }
        
        favorites.insert(code, at: 0)
        favoriteIDs.insert(code.id)
        saveFavorites()
    }
    
    /// Remove a code from favorites
    func removeFavorite(_ code: MedicalCode) {
        favorites.removeAll { $0.id == code.id }
        favoriteIDs.remove(code.id)
        saveFavorites()
    }
    
    func removeFavorite(id: String) {
        favorites.removeAll { $0.id == id }
        favoriteIDs.remove(id)
        saveFavorites()
    }
    
    /// Toggle favorite status
    func toggleFavorite(_ code: MedicalCode) {
        if isFavorite(code) {
            removeFavorite(code)
        } else {
            addFavorite(code)
        }
    }
    
    /// Clear all favorites
    func clearAll() {
        favorites.removeAll()
        favoriteIDs.removeAll()
        saveFavorites()
    }
    
    /// Get favorites count
    var count: Int {
        return favorites.count
    }
    
    /// Get favorites filtered by code type
    func favorites(ofType type: MedicalCodeType) -> [MedicalCode] {
        return favorites.filter { $0.codeType == type }
    }
    
    // MARK: - Private Methods
    
    private func loadFavorites() {
        // Load favorites
        if let data = UserDefaults.standard.data(forKey: storageKey) {
            do {
                favorites = try JSONDecoder().decode([MedicalCode].self, from: data)
                favoriteIDs = Set(favorites.map { $0.id })
            } catch {
                print("❌ Failed to load favorites: \(error)")
            }
        }
    }
    
    private func saveFavorites() {
        do {
            let data = try JSONEncoder().encode(favorites)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            print("❌ Failed to save favorites: \(error)")
        }
    }
}

// MARK: - SwiftUI Preview Support

extension FavoritesManager {
    
    static var preview: FavoritesManager {
        let manager = FavoritesManager()
        manager.favorites = Array(MedicalCode.sampleCodes.prefix(3))
        manager.favoriteIDs = Set(manager.favorites.map { $0.id })
        return manager
    }
}
