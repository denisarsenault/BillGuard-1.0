//
//  FavoritesView.swift
//  BillGuard
//
//  View for displaying saved/favorite codes
//

import SwiftUI

struct FavoritesView: View {
    var body: some View {
        NavigationStack {
            FavoritesViewContent()
        }
    }
}

struct FavoritesViewContent: View {
    
    @EnvironmentObject var appState: AppState
    @State private var selectedCode: MedicalCode?
    @State private var filterType: MedicalCodeType?
    
    private var favoritesManager: FavoritesManager {
        appState.favoritesManager
    }
    
    private var filteredFavorites: [MedicalCode] {
        if let type = filterType {
            return favoritesManager.favorites(ofType: type)
        }
        return favoritesManager.favorites
    }
    
    var body: some View {
        Group {
            if favoritesManager.favorites.isEmpty {
                emptyState
            } else {
                favoritesList
            }
        }
        .navigationTitle("Saved Codes").brandToolbar(title: "Saved Codes")
        
        .toolbar {
            if !favoritesManager.favorites.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Clear All", role: .destructive) {
                            favoritesManager.clearAll()
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .navigationDestination(item: $selectedCode) { code in
            CodeDetailView(code: code)
                .environmentObject(appState)
        }
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: "star.circle")
                .font(.system(size: 80, weight: .light))
                .foregroundColor(.secondary)
            
            Text("No Saved Codes")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Tap the star on any code to save it here for quick access later.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Spacer()
        }
    }
    
    // MARK: - Favorites List
    
    private var favoritesList: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Filter by Code Type
                CodeTypeFilterView(selectedType: $filterType)
                    .padding(.top, 8)
                
                // Count
                HStack {
                    Text("\(filteredFavorites.count) saved code\(filteredFavorites.count == 1 ? "" : "s")")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal)
                
                // List
                LazyVStack(spacing: 12) {
                    ForEach(filteredFavorites) { code in
                        FavoriteCodeRow(
                            code: code,
                            onTap: {
                                selectedCode = code
                            },
                            onRemove: {
                                withAnimation {
                                    favoritesManager.removeFavorite(code)
                                }
                            }
                        )
                    }
                }
                .padding(.horizontal)
            }
            .padding(.bottom, 20)
        }
    }
}

// MARK: - Favorite Code Row

struct FavoriteCodeRow: View {
    
    let code: MedicalCode
    let onTap: () -> Void
    let onRemove: () -> Void
    
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            // Code Badge
            Text(code.codeType.rawValue)
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(codeTypeColor)
                .cornerRadius(6)
            
            // Content
            VStack(alignment: .leading, spacing: 6) {
                Text(code.code)
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Text(code.shortDescription)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                
                if code.hasValidPricing {
                    Text(code.formattedPriceRange)
                        .font(.subheadline)
                        .foregroundColor(.green)
                        .fontWeight(.medium)
                }
            }
            
            Spacer()
            
            // Remove Button
            Button {
                onRemove()
            } label: {
                Image(systemName: "star.fill")
                    .foregroundColor(.yellow)
                    .font(.title3)
            }
        }
        .padding()
        .background(Color("BrandDeepNavy"))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
        .onTapGesture {
            onTap()
        }
    }
    
    private var codeTypeColor: Color {
        switch code.codeType {
        case .cpt: return .blue
        case .icd10: return .green
        case .icd10pcs: return .teal
        case .hcpcs: return .orange
        }
    }
}

#Preview {
    FavoritesView()
        .environmentObject(AppState())
}

#Preview("With Favorites") {
    let appState = AppState()
    appState.favoritesManager.addFavorite(MedicalCode.sampleCodes[0])
    appState.favoritesManager.addFavorite(MedicalCode.sampleCodes[1])
    appState.favoritesManager.addFavorite(MedicalCode.sampleCodes[2])
    
    return FavoritesView()
        .environmentObject(appState)
}
