//
//  HomeView.swift
//  BillGuard
//
//  Home screen with search functionality
//

import SwiftUI
import VisionKit

struct HomeView: View {
    
    @EnvironmentObject var appState: AppState
    @State private var showingCodeDetail = false
    @State private var selectedCode: MedicalCode?
    @State private var showingScanner = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    
                    // Search Bar with Scan Button
                    SearchBarView(
                        searchText: $appState.searchViewModel.searchText,
                        isSearching: appState.searchViewModel.isSearching,
                        onClear: {
                            appState.searchViewModel.clearSearch()
                        },
                        onScanTapped: {
                            showingScanner = true
                        }
                    )
                    .padding(.horizontal)
                    
                    // Code Type Filter
                    CodeTypeFilterView(
                        selectedType: $appState.searchViewModel.selectedCodeType
                    )
                    .onChange(of: appState.searchViewModel.selectedCodeType) { _, _ in
                        // Trigger search when filter changes
                        if !appState.searchViewModel.searchText.isEmpty {
                            Task {
                                await appState.searchViewModel.performSearch(query: appState.searchViewModel.searchText)
                            }
                        }
                    }
                    
                    // Content
                    let _ = print("🎨 HomeView: hasSearched=\(appState.searchViewModel.hasSearched)")
                    
                    if appState.searchViewModel.hasSearched {
                        // Search Results
                        SearchResultsView(
                            results: appState.searchViewModel.searchResults,
                            isSearching: appState.searchViewModel.isSearching,
                            errorMessage: appState.searchViewModel.errorMessage,
                            onSelect: { code in
                                selectedCode = code
                                appState.searchViewModel.recordSearch(code: code)
                            }
                        )
                    } else {
                        // Default Home Content
                        VStack(spacing: 32) {
                            // Recent Searches
                            if !appState.searchViewModel.recentSearchManager.recentSearches.isEmpty {
                                RecentSearchesSection(
                                    searches: appState.searchViewModel.recentSearchManager.recentSearches,
                                    onSelect: { search in
                                        appState.searchViewModel.searchText = search.query
                                    },
                                    onClear: {
                                        appState.searchViewModel.recentSearchManager.clearAll()
                                    }
                                )
                            }
                            
                            // Popular Codes
                            PopularCodesSection(
                                codes: appState.searchViewModel.popularCodes,
                                isLoading: appState.searchViewModel.isLoadingPopular,
                                onSelect: { code in
                                    selectedCode = code
                                }
                            )
                        }
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("BillGuard").brandToolbar(title: "BillGuard MD")
            
            .refreshable {
                appState.searchViewModel.loadPopularCodes()
            }
            .onAppear {
                appState.searchViewModel.loadPopularCodes()
            }
            .navigationDestination(item: $selectedCode) { code in
                CodeDetailView(code: code)
                    .environmentObject(appState)
            }
            .sheet(isPresented: $showingScanner) {
                ScannerSheetFromHome(isPresented: $showingScanner)
                    .environmentObject(appState)
            }
        }
    }
}

// MARK: - Scanner Sheet From Home

struct ScannerSheetFromHome: View {
    @EnvironmentObject var appState: AppState
    @Binding var isPresented: Bool
    @State private var scannerVM: ScannerViewModel?
    @State private var selectedCode: MedicalCode?
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let vm = scannerVM {
                    if vm.scannedCodes.isEmpty {
                        // Show scanner directly
                        ScannerCameraView(scannerVM: vm)
                    } else {
                        // Show scanned codes list with option to scan more
                        ScannedCodesListView(
                            scannerVM: vm,
                            onCodeSelected: { code in
                                selectedCode = code
                            },
                            onSave: { scannedCode in
                                if let medicalCode = scannedCode.matchedMedicalCode {
                                    appState.favoritesManager.addFavorite(medicalCode)
                                }
                            },
                            isSaved: { scannedCode in
                                scannedCode.matchedMedicalCode.map { appState.favoritesManager.isFavorite($0) } ?? false
                            }
                        )
                    }
                } else {
                    ProgressView("Loading scanner...")
                }
            }
            .navigationTitle("Scan Codes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        isPresented = false
                    }
                    .fontWeight(.semibold)
                }
            }
            .navigationDestination(item: $selectedCode) { code in
                CodeDetailView(code: code)
                    .environmentObject(appState)
            }
            .onAppear {
                if scannerVM == nil {
                    scannerVM = ScannerViewModel(cloudKitService: appState.cloudKitService)
                }
            }
        }
    }
}

// MARK: - Scanner Camera View

struct ScannerCameraView: View {
    @ObservedObject var scannerVM: ScannerViewModel
    @State private var isScanning = true
    @State private var showTapFeedback = false
    @State private var codesFoundInTap = 0
    
    var body: some View {
        ZStack {
            if DataScannerRepresentable.isSupported && DataScannerRepresentable.isAvailable {
                DataScannerRepresentable(
                    onTextTapped: { text in
                        handleTextTapped(text)
                    },
                    onError: { error in
                        print("Scanner error: \(error)")
                    },
                    isScanning: $isScanning
                )
                .ignoresSafeArea()
                
                // Overlay
                VStack {
                    Text("Tap highlighted text to capture codes")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial)
                        .cornerRadius(20)
                        .padding(.top, 10)
                    
                    Spacer()
                    
                    if showTapFeedback {
                        HStack {
                            if codesFoundInTap > 0 {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("\(codesFoundInTap) code\(codesFoundInTap == 1 ? "" : "s") added")
                                    .fontWeight(.medium)
                            } else {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.orange)
                                Text("No medical code found")
                                    .fontWeight(.medium)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(.ultraThinMaterial)
                        .cornerRadius(25)
                        .transition(.scale.combined(with: .opacity))
                    }
                    
                    if !scannerVM.scannedCodes.isEmpty {
                        HStack {
                            Image(systemName: "doc.text.fill")
                                .foregroundColor(.accentColor)
                            Text("\(scannerVM.scannedCodes.count) code\(scannerVM.scannedCodes.count == 1 ? "" : "s") captured")
                                .fontWeight(.medium)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(.ultraThinMaterial)
                        .cornerRadius(25)
                        .padding(.bottom, 30)
                    } else {
                        Spacer().frame(height: 60)
                    }
                }
            } else {
                ScannerAvailabilityView()
            }
        }
    }
    
    private func handleTextTapped(_ text: String) {
        let previousCount = scannerVM.scannedCodes.count
        scannerVM.processTappedText(text)
        let newCount = scannerVM.scannedCodes.count
        codesFoundInTap = newCount - previousCount
        
        withAnimation(.easeInOut(duration: 0.2)) {
            showTapFeedback = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeInOut(duration: 0.3)) {
                showTapFeedback = false
            }
        }
    }
}

// MARK: - Scanned Codes List View

struct ScannedCodesListView: View {
    @ObservedObject var scannerVM: ScannerViewModel
    let onCodeSelected: (MedicalCode) -> Void
    let onSave: (ScannedCode) -> Void
    let isSaved: (ScannedCode) -> Bool
    
    @State private var showingScanner = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Scan More Button
            Button {
                showingScanner = true
            } label: {
                HStack {
                    Image(systemName: "camera.fill").font(.title3).frame(width: 30)
                    Text("Scan More Codes").fontWeight(.semibold)
                    Spacer()
                    Image(systemName: "chevron.right").foregroundColor(.white)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.accentColor)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .padding()
            
            HStack {
                Text("\(scannerVM.scannedCodes.count) code\(scannerVM.scannedCodes.count == 1 ? "" : "s") found")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
            
            List {
                ForEach(scannerVM.scannedCodes) { scannedCode in
                    ScannedCodeRow(
                        scannedCode: scannedCode,
                        onTap: {
                            if let medicalCode = scannedCode.matchedMedicalCode {
                                onCodeSelected(medicalCode)
                            }
                        },
                        onSave: {
                            onSave(scannedCode)
                        },
                        isSaved: isSaved(scannedCode)
                    )
                }
                .onDelete { offsets in
                    scannerVM.removeCode(at: offsets)
                }
            }
            .listStyle(.plain)
        }
        .sheet(isPresented: $showingScanner) {
            NavigationStack {
                ScannerCameraView(scannerVM: scannerVM)
                    .navigationTitle("Scanning")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button("Done") {
                                showingScanner = false
                            }
                            .fontWeight(.semibold)
                        }
                    }
            }
        }
    }
}

// MARK: - Search Bar View

struct SearchBarView: View {
    
    @Binding var searchText: String
    let isSearching: Bool
    let onClear: () -> Void
    let onScanTapped: () -> Void
    
    @FocusState private var isFocused: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.title3)
                    .foregroundColor(.secondary)
                
                TextField("Search medical codes...", text: $searchText)
                    .font(.title3)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($isFocused)
                
                if !searchText.isEmpty {
                    if isSearching {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Button {
                            onClear()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color("BrandNavy"))
            .cornerRadius(14)
            
            // Scan Button
            Button {
                onScanTapped()
            } label: {
                Image(systemName: "camera.viewfinder")
                    .font(.title2)
                    .foregroundColor(.white)
                    .frame(width: 52, height: 52)
                    .background(Color.accentColor)
                    .cornerRadius(14)
            }
        }
    }
}

// MARK: - Code Type Filter

struct CodeTypeFilterView: View {
    
    @Binding var selectedType: MedicalCodeType?
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                FilterChip(
                    title: "All",
                    isSelected: selectedType == nil,
                    action: { selectedType = nil }
                )
                
                ForEach(MedicalCodeType.allCases, id: \.self) { type in
                    FilterChip(
                        title: type.rawValue,
                        isSelected: selectedType == type,
                        action: { selectedType = type }
                    )
                }
            }
            .padding(.horizontal)
        }
    }
}

struct FilterChip: View {
    
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundColor(isSelected ? .white : .primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(isSelected ? Color("BrandCyan") : Color("BrandNavy"))
                .cornerRadius(20)
        }
    }
}

// MARK: - Search Results View

struct SearchResultsView: View {
    
    let results: [MedicalCode]
    let isSearching: Bool
    let errorMessage: String?
    let onSelect: (MedicalCode) -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            let _ = print("🎨 SearchResultsView: results.count=\(results.count), isSearching=\(isSearching), errorMessage=\(errorMessage ?? "nil")")
            
            if let error = errorMessage {
                // Error State
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 40)
                
            } else if results.isEmpty && !isSearching {
                // No Results
                VStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No codes found")
                        .font(.title3)
                        .fontWeight(.medium)
                    Text("Try a different search term or code number")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 40)
                
            } else {
                // Results Header
                HStack {
                    Text("\(results.count) result\(results.count == 1 ? "" : "s")")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal)
                
                // Results List
                LazyVStack(spacing: 12) {
                    ForEach(results) { code in
                        CodeRowView(code: code)
                            .onTapGesture {
                                onSelect(code)
                            }
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

// MARK: - Code Row View

struct CodeRowView: View {
    
    let code: MedicalCode
    
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
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .background(Color("BrandNavy"))
        .cornerRadius(12)
    }
    
    private var codeTypeColor: Color {
        switch code.codeType {
        case .cpt: return Color("BrandCyan")
        case .icd10: return .green
        case .icd10pcs: return .teal
        case .hcpcs: return .orange
        }
    }
}

// MARK: - Recent Searches Section

struct RecentSearchesSection: View {
    
    let searches: [RecentSearch]
    let onSelect: (RecentSearch) -> Void
    let onClear: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent Searches")
                    .font(.title3)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button("Clear") {
                    onClear()
                }
                .font(.subheadline)
                .foregroundColor(.accentColor)
            }
            .padding(.horizontal)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(searches) { search in
                        Button {
                            onSelect(search)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.caption)
                                Text(search.displayText)
                                    .font(.subheadline)
                                    .lineLimit(1)
                            }
                            .foregroundColor(.primary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Color("BrandNavy"))
                            .cornerRadius(20)
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

// MARK: - Popular Codes Section

struct PopularCodesSection: View {
    
    let codes: [MedicalCode]
    let isLoading: Bool
    let onSelect: (MedicalCode) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Popular Codes")
                .font(.title3)
                .fontWeight(.semibold)
                .padding(.horizontal)
            
            if isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .padding(.vertical, 40)
            } else if codes.isEmpty {
                Text("No popular codes available")
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(codes) { code in
                        CodeRowView(code: code)
                            .onTapGesture {
                                onSelect(code)
                            }
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

#Preview {
    HomeView()
        .environmentObject(AppState())
}
