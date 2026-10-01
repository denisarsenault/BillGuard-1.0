//
//  MainTabView.swift
//  BillGuard
//
//  Main tab navigation view
//

import SwiftUI
import Vision

// MARK: - Brand Navigation Title

/// Toolbar modifier: logo pinned to left, title centered, optional patient name below
struct BrandToolbar: ViewModifier {
    var title: String = "BillGuard MD"
    var showPatient: Bool = false
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var patientDataService: PatientDataService
    
    private var patientName: String? {
        guard showPatient,
              let id = appState.selectedPatientId,
              let patient = patientDataService.patients.first(where: { $0.id == id })
        else { return nil }
        return patient.fullName
    }
    
    func body(content: Content) -> some View {
        content
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Image("BrandLogo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 32, height: 32)
                }
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 1) {
                        Text(title)
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color("BrandCyan"), Color("BrandTeal")],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                        
                        if let name = patientName {
                            Text(name)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(Color("BrandCyan").opacity(0.6))
                        }
                    }
                }
            }
    }
}

extension View {
    func brandToolbar(title: String = "BillGuard MD", showPatient: Bool = false) -> some View {
        modifier(BrandToolbar(title: title, showPatient: showPatient))
    }
}

// MARK: - Main Tab View

struct MainTabView: View {
    
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var patientDataService: PatientDataService
    @EnvironmentObject var userManager: UserManager
    
    @State private var showingProfileMenu = false
    
    // Tab definitions
    private let tabs: [(icon: String, label: String)] = [
        ("magnifyingglass", "Search & Add"),
        ("doc.text.fill", "Bills"),
        ("person.2.fill", "Patients"),
        ("building.2.fill", "Providers"),
        ("star.fill", "Saved"),
        ("shield.lefthalf.filled", "Insurance"),
        ("calendar.badge.clock", "Visits"),
        ("creditcard.fill", "Payments"),
        ("gearshape.fill", "Settings")
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // Content area
            Group {
                switch appState.selectedTab {
                case 0:
                    HomeViewWithProfile()
                case 1:
                    BillsListViewWithProfile()
                case 2:
                    PatientListViewWithProfile()
                case 3:
                    ProviderListViewWithProfile()
                case 4:
                    FavoritesViewWithProfile()
                case 5:
                    InsuranceTabView()
                case 6:
                    VisitsTabView()
                case 7:
                    PaymentsTabView()
                case 8:
                    SettingsTabView()
                default:
                    HomeViewWithProfile()
                }
            }
            .environmentObject(appState)
            .environmentObject(patientDataService)
            .environmentObject(userManager)
            .frame(maxHeight: .infinity)
            
            Divider()
            
            // Scrollable Tab Bar
            ScrollableTabBar(
                tabs: tabs,
                selectedTab: $appState.selectedTab,
                favoritesCount: appState.favoritesManager.count
            )
        }
        // Front-desk coaching "balloon" that appears when you arrive at a
        // health facility (saved provider geofence, or an opt-in nearby match).
        .overlay { BalloonCoachOverlay() }
    }
}

// MARK: - Arrival Coaching Balloon

/// Interactive "balloon" that drops from the top when the user arrives at a
/// health facility, coaching them on what to ask at the front desk. Styled
/// after MapMe's GuardianBalloonOverlay (thin material, spring-in) but
/// interactive so the user can tick questions off while they stand in line.
struct BalloonCoachOverlay: View {
    @ObservedObject private var coach = ArrivalCoach.shared
    @State private var checked: Set<UUID> = []

    var body: some View {
        if let prompt = coach.prompt {
            ZStack(alignment: .top) {
                Color.black.opacity(0.28).ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture { dismiss() }
                card(prompt)
                    .padding(.horizontal, 16)
                    .padding(.top, 54)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            .animation(.spring(response: 0.45, dampingFraction: 0.85), value: coach.prompt?.id)
            .onAppear { coach.expireIfStale() }
        }
    }

    private func card(_ prompt: ArrivalPrompt) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "mappin.circle.fill")
                    .font(.title2).foregroundStyle(.teal)
                VStack(alignment: .leading, spacing: 1) {
                    Text("You've arrived at").font(.caption).foregroundStyle(.secondary)
                    Text(prompt.facilityName).font(.headline)
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3).foregroundStyle(.secondary)
                }.buttonStyle(.plain)
            }

            Text("Ask at the front desk")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.teal)
                .textCase(.uppercase)

            VStack(spacing: 8) {
                ForEach(prompt.questions) { q in
                    questionRow(q)
                }
            }

            Button {
                dismiss()
            } label: {
                Text("Got it")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.teal, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.white)
            }.buttonStyle(.plain)
        }
        .padding(18)
        .frame(maxWidth: 460)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 16, y: 8)
    }

    private func questionRow(_ q: CoachQuestion) -> some View {
        let isOn = checked.contains(q.id)
        return Button {
            if isOn { checked.remove(q.id) } else { checked.insert(q.id) }
        } label: {
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: isOn ? "checkmark.circle.fill" : q.icon)
                    .font(.body)
                    .foregroundStyle(isOn ? Color.green : Color.teal)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(q.text)
                        .font(.subheadline.weight(.medium))
                        .strikethrough(isOn, color: .secondary)
                        .foregroundStyle(isOn ? .secondary : .primary)
                    if let detail = q.detail {
                        Text(detail).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func dismiss() {
        withAnimation(.easeInOut(duration: 0.2)) { coach.dismiss() }
        checked.removeAll()
    }
}

// MARK: - Scrollable Tab Bar

struct ScrollableTabBar: View {
    let tabs: [(icon: String, label: String)]
    @Binding var selectedTab: Int
    var favoritesCount: Int = 0
    
    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(0..<tabs.count, id: \.self) { index in
                        let tab = tabs[index]
                        let isSelected = selectedTab == index
                        
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedTab = index
                            }
                        } label: {
                            VStack(spacing: 4) {
                                ZStack(alignment: .topTrailing) {
                                    Image(systemName: tab.icon)
                                        .font(.system(size: 20))
                                    
                                    // Badge for Saved tab
                                    if index == 4 && favoritesCount > 0 {
                                        Text("\(favoritesCount)")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundColor(.white)
                                            .frame(minWidth: 16, minHeight: 16)
                                            .background(Color.red)
                                            .clipShape(Circle())
                                            .offset(x: 8, y: -6)
                                    }
                                }
                                .frame(height: 24)
                                
                                Text(tab.label)
                                    .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                            }
                            .foregroundColor(isSelected ? Color("BrandCyan") : Color("BrandCyan").opacity(0.35))
                            .frame(width: 76, height: 50)
                        }
                        .id(index)
                    }
                }
                .padding(.horizontal, 4)
            }
            .onChange(of: selectedTab) { _, newTab in
                withAnimation {
                    scrollProxy.scrollTo(newTab, anchor: .center)
                }
            }
        }
        .frame(height: 56)
        .background(
            Color("BrandNavy")
                .shadow(color: Color("BrandCyan").opacity(0.1), radius: 2, y: -1)
        )
    }
}

// MARK: - Patient-Dependent Tab Wrappers

struct InsuranceTabView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var patientDataService: PatientDataService
    
    var body: some View {
        NavigationStack {
            if let patientId = appState.selectedPatientId {
                InsuranceListView(patientId: patientId)
                    .environmentObject(patientDataService)
                    .environmentObject(appState)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            ProfileMenuButton()
                        }
                    }
            } else {
                NoPatientPlaceholder(feature: "Insurance", icon: "shield.lefthalf.filled")
            }
        }
    }
}

struct VisitsTabView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var patientDataService: PatientDataService
    
    var body: some View {
        NavigationStack {
            if let patientId = appState.selectedPatientId {
                VisitListView(patientId: patientId)
                    .environmentObject(patientDataService)
                    .environmentObject(appState)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            ProfileMenuButton()
                        }
                    }
            } else {
                NoPatientPlaceholder(feature: "Visits", icon: "calendar.badge.clock")
            }
        }
    }
}

struct PaymentsTabView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var patientDataService: PatientDataService
    
    var body: some View {
        NavigationStack {
            if let patientId = appState.selectedPatientId {
                PaymentMethodListView(patientId: patientId)
                    .environmentObject(patientDataService)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            ProfileMenuButton()
                        }
                    }
            } else {
                NoPatientPlaceholder(feature: "Payment Methods", icon: "creditcard.fill")
            }
        }
    }
}

struct SettingsTabView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var patientDataService: PatientDataService
    @EnvironmentObject var userManager: UserManager
    
    var body: some View {
        NavigationStack {
            SettingsView()
                .environmentObject(appState)
                .environmentObject(patientDataService)
                .environmentObject(userManager)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button {
                            withAnimation {
                                appState.selectedTab = 0
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 14, weight: .semibold))
                                Text("Done")
                                    .fontWeight(.semibold)
                            }
                            .foregroundColor(Color("BrandCyan"))
                        }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        ProfileMenuButton()
                    }
                }
        }
    }
}

// MARK: - No Patient Placeholder

struct NoPatientPlaceholder: View {
    let feature: String
    let icon: String
    
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: icon)
                .font(.system(size: 56))
                .foregroundStyle(.tertiary)
            
            Text("No Patient Selected")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Select a patient from the Patients tab to view \(feature.lowercased()).")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Spacer()
            Spacer()
        }
        .navigationTitle(feature)
        .brandToolbar(title: feature, showPatient: true)
    }
}

// MARK: - Profile Menu Button

struct ProfileMenuButton: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var userManager: UserManager
    @EnvironmentObject var patientDataService: PatientDataService
    
    @State private var showingProfile = false
    @State private var showingSettings = false
    @State private var showingAbout = false
    
    var body: some View {
        Menu {
            // User info section
            if let user = userManager.currentUser {
                Section {
                    Label(user.displayName, systemImage: "person.fill")
                    Text(user.email)
                        .font(.caption)
                }
            }
            
            Divider()
            
            // Patient selection
            Section("Active Patient") {
                ForEach(patientDataService.patients) { patient in
                    Button {
                        appState.selectPatient(patient.id)
                    } label: {
                        HStack {
                            Text(patient.fullName)
                            if patient.id == appState.selectedPatientId {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
            
            Divider()
            
            // Actions
            Button {
                showingProfile = true
            } label: {
                Label("My Profile", systemImage: "person.circle")
            }
            
            Button {
                showingSettings = true
            } label: {
                Label("Settings", systemImage: "gear")
            }
            
            Button {
                showingAbout = true
            } label: {
                Label("About BillGuard", systemImage: "info.circle")
            }
            
            Divider()
            
            Button(role: .destructive) {
                appState.logout()
            } label: {
                Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
            }
        } label: {
            profileAvatar
        }
        .sheet(isPresented: $showingProfile) {
            NavigationStack {
                ProfileDetailView()
                    .environmentObject(appState)
                    .environmentObject(userManager)
                    .environmentObject(patientDataService)
            }
        }
        .sheet(isPresented: $showingSettings) {
            NavigationStack {
                SettingsView()
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") {
                                showingSettings = false
                            }
                            .fontWeight(.semibold)
                            .foregroundColor(Color("BrandCyan"))
                        }
                    }
            }
        }
        .sheet(isPresented: $showingAbout) {
            InfoView()
        }
    }
    
    private var profileAvatar: some View {
        Group {
            if let user = userManager.currentUser {
                ZStack {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 32, height: 32)
                    
                    Text(user.displayName.prefix(1).uppercased())
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                }
            } else {
                Image(systemName: "person.circle.fill")
                    .font(.title2)
                    .foregroundColor(.accentColor)
            }
        }
    }
}

// MARK: - Views With Profile Button

struct HomeViewWithProfile: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedCode: MedicalCode?
    @State private var showingScanner = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if appState.searchViewModel.hasSearched {
                    // Search results mode
                    ScrollView {
                        VStack(spacing: 16) {
                            CodeTypeFilterView(
                                selectedType: $appState.searchViewModel.selectedCodeType
                            )
                            .onChange(of: appState.searchViewModel.selectedCodeType) { _, _ in
                                if !appState.searchViewModel.searchText.isEmpty {
                                    Task {
                                        await appState.searchViewModel.performSearch(query: appState.searchViewModel.searchText)
                                    }
                                }
                            }
                            
                            SearchResultsView(
                                results: appState.searchViewModel.searchResults,
                                isSearching: appState.searchViewModel.isSearching,
                                errorMessage: appState.searchViewModel.errorMessage,
                                onSelect: { code in
                                    selectedCode = code
                                    appState.searchViewModel.recordSearch(code: code)
                                }
                            )
                        }
                        .padding(.vertical, 8)
                    }
                } else {
                    // Default mode: camera → filters → popular codes
                    ScrollView {
                        VStack(spacing: 20) {
                            // Camera scan button — centered and prominent
                            Button {
                                showingScanner = true
                            } label: {
                                Image(systemName: "camera.viewfinder")
                                    .font(.system(size: 44))
                                    .foregroundColor(Color("BrandCyan"))
                                    .frame(width: 90, height: 90)
                                    .background(Color("BrandNavy"))
                                    .cornerRadius(22)
                                    .shadow(color: Color("BrandCyan").opacity(0.3), radius: 12)
                            }
                            .padding(.top, 8)
                            
                            // Code type filter pills
                            CodeTypeFilterView(
                                selectedType: $appState.searchViewModel.selectedCodeType
                            )
                            
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
                        .padding(.vertical, 8)
                    }
                }
                
                // Search bar pinned to bottom
                BottomSearchBar(
                    searchText: $appState.searchViewModel.searchText,
                    isSearching: appState.searchViewModel.isSearching,
                    onClear: {
                        appState.searchViewModel.clearSearch()
                    }
                )
            }
            .navigationTitle("Search & Add Code").brandToolbar(title: "Search & Add Code")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    ProfileMenuButton()
                }
            }
            .navigationDestination(item: $selectedCode) { code in
                CodeDetailView(code: code)
                    .environmentObject(appState)
            }
            .sheet(isPresented: $showingScanner) {
                ScannerView(addToDBMode: true)
                    .environmentObject(appState)
            }
            .refreshable {
                appState.searchViewModel.loadPopularCodes()
            }
            .onAppear {
                appState.searchViewModel.loadPopularCodes()
            }
        }
    }
}

// MARK: - Bottom Search Bar

struct BottomSearchBar: View {
    @Binding var searchText: String
    let isSearching: Bool
    let onClear: () -> Void
    @FocusState private var isFocused: Bool
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            
            TextField("Search medical codes...", text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($isFocused)
            
            if !searchText.isEmpty {
                if isSearching {
                    ProgressView().scaleEffect(0.7)
                } else {
                    Button { onClear() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color("BrandNavy"))
        .cornerRadius(14)
        .padding(.horizontal)
        .padding(.bottom, 8)
    }
}

struct BillsListViewWithProfile: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var patientDataService: PatientDataService
    @State private var navigationPath = NavigationPath()
    
    var body: some View {
        NavigationStack(path: $navigationPath) {
            BillsListViewContent(navigationPath: $navigationPath)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        ProfileMenuButton()
                    }
                }
                .navigationDestination(for: String.self) { claimId in
                    if let claim = patientDataService.claims.first(where: { $0.id == claimId }) {
                        BillMainView(claim: claim)
                            .environmentObject(patientDataService)
                            .environmentObject(appState)
                            .onAppear {
                                appState.clearNewBadge(for: claimId)
                            }
                    }
                }
        }
        .onChange(of: appState.lastSavedClaimId) { _, _ in
            // Pop to bills list root (in case user was viewing another bill)
            navigationPath = NavigationPath()
        }
    }
}

struct PatientListViewWithProfile: View {
    var body: some View {
        NavigationStack {
            PatientListViewContent()
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        ProfileMenuButton()
                    }
                }
        }
    }
}

struct ProviderListViewWithProfile: View {
    @EnvironmentObject var patientDataService: PatientDataService
    
    var body: some View {
        NavigationStack {
            ProviderListViewContent()
                .environmentObject(patientDataService)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        ProfileMenuButton()
                    }
                }
        }
    }
}

struct FavoritesViewWithProfile: View {
    var body: some View {
        NavigationStack {
            FavoritesViewContent()
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        ProfileMenuButton()
                    }
                }
        }
    }
}

// MARK: - Profile Detail View (Sheet)

struct ProfileDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var userManager: UserManager
    @EnvironmentObject var patientDataService: PatientDataService
    
    @State private var showingAddPatient = false
    
    var body: some View {
        List {
            // User Info Section
            Section {
                if let user = userManager.currentUser {
                    HStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(Color.accentColor)
                                .frame(width: 60, height: 60)
                            
                            Text(user.displayName.prefix(2).uppercased())
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(user.displayName)
                                .font(.headline)
                            Text(user.email)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            
            // Patients Section
            Section("My Patients") {
                ForEach(patientDataService.patients) { patient in
                    PatientRow(
                        patient: patient,
                        isSelected: patient.id == appState.selectedPatientId
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        appState.selectPatient(patient.id)
                    }
                }
                .onDelete(perform: deletePatients)
                
                Button {
                    showingAddPatient = true
                } label: {
                    Label("Add Patient", systemImage: "person.badge.plus")
                }
            }
            
            // Quick Stats
            Section("Summary") {
                if let patientId = appState.selectedPatientId {
                    let balance = patientDataService.totalOutstandingBalance(for: patientId)
                    HStack {
                        Text("Outstanding Balance")
                        Spacer()
                        Text(balance, format: .currency(code: "USD"))
                            .fontWeight(.semibold)
                            .foregroundColor(balance > 0 ? .red : .green)
                    }
                    
                    HStack {
                        Text("Total Claims")
                        Spacer()
                        Text("\(patientDataService.claims(for: patientId).count)")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Providers")
                        Spacer()
                        Text("\(patientDataService.providers.count)")
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text("Select a patient to see summary")
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    dismiss()
                }
            }
        }
        .sheet(isPresented: $showingAddPatient) {
            AddPatientView()
                .environmentObject(patientDataService)
        }
    }
    
    private func deletePatients(at offsets: IndexSet) {
        for index in offsets {
            let patient = patientDataService.patients[index]
            patientDataService.deletePatient(patient)
            if patient.id == appState.selectedPatientId {
                appState.selectedPatientId = patientDataService.patients.first?.id
            }
        }
    }
}

// MARK: - Procedure Code Scanner View (for Procedure Code Mode)

struct ProcedureCodeScannerView: View {
    @EnvironmentObject var appState: AppState
    
    @State private var showingCamera = false
    @State private var showingPhotoLibrary = false
    @State private var showingFilePicker = false
    @State private var selectedImage: UIImage?
    @State private var isProcessing = false
    @State private var extractedCodes: [ExtractedProcedureLine] = []
    @State private var extractedText = ""
    @State private var showingResults = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if showingResults {
                    resultsView
                } else if isProcessing {
                    processingView
                } else {
                    sourceSelectionView
                }
            }
            .navigationTitle("Scan Procedure Codes")
            .toolbar {
                if showingResults {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("New Scan") {
                            resetScanner()
                        }
                    }
                }
            }
            .fullScreenCover(isPresented: $showingCamera) {
                SmartDocumentScanner(capturedImage: $selectedImage)
            }
            .sheet(isPresented: $showingPhotoLibrary) {
                PhotoPicker(image: $selectedImage)
            }
            .sheet(isPresented: $showingFilePicker) {
                FilePicker(image: $selectedImage)
            }
            .onChange(of: selectedImage) { _, newImage in
                if newImage != nil {
                    processImage()
                }
            }
        }
    }
    
    private var sourceSelectionView: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer().frame(height: 20)
                
                // Icon
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.1))
                        .frame(width: 120, height: 120)
                    
                    Image(systemName: "doc.text.viewfinder")
                        .font(.system(size: 50))
                        .foregroundColor(.accentColor)
                }
                
                VStack(spacing: 8) {
                    Text("Scan Procedure Codes")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("Use OCR to extract CPT, HCPCS, and ICD-10\ncodes from medical documents")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                
                // Source Options
                VStack(spacing: 12) {
                    Button {
                        showingCamera = true
                    } label: {
                        ScanSourceRow(
                            icon: "camera.fill",
                            title: "Take Photo",
                            subtitle: "Use camera to capture document",
                            color: .blue
                        )
                    }
                    .buttonStyle(.plain)
                    
                    Button {
                        showingPhotoLibrary = true
                    } label: {
                        ScanSourceRow(
                            icon: "photo.on.rectangle",
                            title: "Photo Library",
                            subtitle: "Select from saved photos",
                            color: .green
                        )
                    }
                    .buttonStyle(.plain)
                    
                    Button {
                        showingFilePicker = true
                    } label: {
                        ScanSourceRow(
                            icon: "folder.fill",
                            title: "Files",
                            subtitle: "Import PDF or image files",
                            color: .orange
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal)
                
                // Supported Codes Info
                VStack(alignment: .leading, spacing: 12) {
                    Text("Supported Code Types")
                        .font(.headline)
                    
                    HStack(spacing: 16) {
                        CodeTypeBadge(type: "CPT", color: .blue)
                        CodeTypeBadge(type: "HCPCS", color: .green)
                        CodeTypeBadge(type: "ICD-10", color: .purple)
                    }
                    
                    Text("Codes will be matched against our database to show descriptions and typical costs.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color("BrandNavy"))
                .cornerRadius(12)
                .padding(.horizontal)
                
                Spacer()
            }
        }
    }
    
    private var processingView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            if let image = selectedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 200)
                    .cornerRadius(12)
                    .shadow(radius: 5)
            }
            
            Loading3DRingView(size: 60, color: .accentColor)
            
            VStack(spacing: 8) {
                Text("Analyzing Document...")
                    .font(.headline)
                Text("Extracting procedure codes")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding()
    }
    
    private var resultsView: some View {
        VStack(spacing: 0) {
            if extractedCodes.isEmpty {
                VStack(spacing: 20) {
                    Spacer()
                    
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 50))
                        .foregroundColor(.secondary)
                    
                    Text("No procedure codes found")
                        .font(.headline)
                    
                    if !extractedText.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Extracted text:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            ScrollView {
                                Text(extractedText)
                                    .font(.caption2)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxHeight: 150)
                            .padding()
                            .background(Color("BrandNavy"))
                            .cornerRadius(8)
                        }
                        .padding()
                    }
                    
                    Button("Try Again") {
                        resetScanner()
                    }
                    .buttonStyle(.borderedProminent)
                    
                    Spacer()
                }
            } else {
                List {
                    Section {
                        ForEach(extractedCodes) { proc in
                            NavigationLink {
                                if let matched = proc.matchedCode {
                                    CodeDetailView(code: matched)
                                        .environmentObject(appState)
                                } else {
                                    ProcedureModeCodeDetailView(procedure: proc)
                                        .environmentObject(appState)
                                }
                            } label: {
                                ProcedureModeCodeRow(procedure: proc)
                            }
                        }
                    } header: {
                        Text("Found \(extractedCodes.count) code(s)")
                    }
                    
                    Section {
                        if !extractedText.isEmpty {
                            DisclosureGroup("View Raw Text") {
                                Text(extractedText)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
    }
    
    private func resetScanner() {
        selectedImage = nil
        showingResults = false
        extractedText = ""
        extractedCodes = []
    }
    
    private func processImage() {
        guard let image = selectedImage else { return }
        isProcessing = true
        
        Task {
            do {
                let text = try await extractText(from: image)
                let codes = parseProcedureCodes(from: text)
                
                await MainActor.run {
                    extractedText = text
                    extractedCodes = codes
                    isProcessing = false
                    showingResults = true
                }
            } catch {
                await MainActor.run {
                    extractedText = "Error: \(error.localizedDescription)"
                    isProcessing = false
                    showingResults = true
                }
            }
        }
    }
    
    private func extractText(from image: UIImage) async throws -> String {
        guard let cgImage = image.cgImage else {
            throw NSError(domain: "Scanner", code: 1)
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: "")
                    return
                }
                
                let text = observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
                continuation.resume(returning: text)
            }
            
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try? handler.perform([request])
        }
    }
    
    private func parseProcedureCodes(from text: String) -> [ExtractedProcedureLine] {
        var procedures: [ExtractedProcedureLine] = []
        let lines = text.components(separatedBy: .newlines)
        
        let cptPattern = #"\b\d{5}\b"#
        let hcpcsPattern = #"\b[A-Z]\d{4}\b"#
        let icd10Pattern = #"\b[A-Z]\d{2}\.?\d{0,4}\b"#
        let amountPattern = #"\$?\s*\d{1,3}(?:,\d{3})*(?:\.\d{2})?"#
        
        for line in lines {
            var procedure = ExtractedProcedureLine()
            var foundCode = false
            
            if let codeMatch = line.range(of: cptPattern, options: .regularExpression) {
                procedure.code = String(line[codeMatch])
                foundCode = true
            } else if let codeMatch = line.range(of: hcpcsPattern, options: .regularExpression) {
                procedure.code = String(line[codeMatch])
                foundCode = true
            } else if let codeMatch = line.range(of: icd10Pattern, options: .regularExpression) {
                let potentialCode = String(line[codeMatch])
                if potentialCode.count >= 3 {
                    procedure.code = potentialCode
                    foundCode = true
                }
            }
            
            if foundCode {
                if let amountRegex = try? Regex(amountPattern) {
                    let amounts = line.matches(of: amountRegex).compactMap { match -> Double? in
                        let str = String(line[match.range])
                            .replacingOccurrences(of: "$", with: "")
                            .replacingOccurrences(of: ",", with: "")
                            .trimmingCharacters(in: .whitespaces)
                        return Double(str)
                    }
                    
                    if let lastAmount = amounts.last {
                        procedure.totalCost = lastAmount
                    }
                }
                
                var desc = line
                desc = desc.replacingOccurrences(of: procedure.code, with: "")
                if let amountRegex = try? Regex(amountPattern) {
                    for match in line.matches(of: amountRegex) {
                        desc = desc.replacingOccurrences(of: String(line[match.range]), with: "")
                    }
                }
                procedure.description = desc
                    .trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "|-:•·"))
                    .trimmingCharacters(in: .whitespaces)
                
                if let match = appState.cloudKitService.lookupCode(procedure.code) {
                    procedure.matchedCode = match
                    procedure.normalCostLow = match.priceLow
                    procedure.normalCostHigh = match.priceHigh
                    procedure.normalCostAverage = match.priceAverage
                    
                    if procedure.description.count < 5 {
                        procedure.description = match.shortDescription
                    }
                }
                
                if !procedure.code.isEmpty {
                    procedures.append(procedure)
                }
            }
        }
        
        var seen = Set<String>()
        procedures = procedures.filter { proc in
            if seen.contains(proc.code) { return false }
            seen.insert(proc.code)
            return true
        }
        
        return procedures
    }
}

// MARK: - Supporting Views for Procedure Code Mode

struct ScanSourceRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.white)
                .frame(width: 50, height: 50)
                .background(color)
                .cornerRadius(12)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color("BrandNavy"))
        .cornerRadius(12)
    }
}

struct CodeTypeBadge: View {
    let type: String
    let color: Color
    
    var body: some View {
        Text(type)
            .font(.caption)
            .fontWeight(.semibold)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(color.opacity(0.15))
            .foregroundColor(color)
            .cornerRadius(8)
    }
}

struct ProcedureModeCodeRow: View {
    let procedure: ExtractedProcedureLine
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(procedure.code)
                    .font(.system(.headline, design: .monospaced))
                    .foregroundColor(.accentColor)
                
                if procedure.matchedCode != nil {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                }
                
                Spacer()
                
                if procedure.totalCost > 0 {
                    Text(procedure.totalCost, format: .currency(code: "USD"))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            
            Text(procedure.description.isEmpty ? "No description" : procedure.description)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(2)
            
            if procedure.hasCostComparison {
                Text("Typical: \(procedure.normalCostLow ?? 0, format: .currency(code: "USD")) – \(procedure.normalCostHigh ?? 0, format: .currency(code: "USD"))")
                    .font(.caption)
                    .foregroundColor(procedure.costStatus.color)
            }
        }
        .padding(.vertical, 4)
    }
}

struct ProcedureModeCodeDetailView: View {
    let procedure: ExtractedProcedureLine
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Code Header
                VStack(spacing: 12) {
                    Text(procedure.code)
                        .font(.system(.largeTitle, design: .monospaced))
                        .fontWeight(.bold)
                        .foregroundColor(.accentColor)
                    
                    Text(procedure.description)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                    
                    Text("Scanned Code")
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.orange.opacity(0.1))
                        .foregroundColor(.orange)
                        .cornerRadius(20)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color("BrandNavy"))
                .cornerRadius(12)
                
                // Cost Info
                if procedure.totalCost > 0 {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Scanned Cost")
                            .font(.headline)
                        
                        HStack {
                            Text("Amount")
                            Spacer()
                            Text(procedure.totalCost, format: .currency(code: "USD"))
                                .fontWeight(.semibold)
                        }
                        
                        if procedure.hasCostComparison {
                            HStack {
                                Text("Typical Range")
                                Spacer()
                                Text("\(procedure.normalCostLow ?? 0, format: .currency(code: "USD")) – \(procedure.normalCostHigh ?? 0, format: .currency(code: "USD"))")
                                    .foregroundColor(procedure.costStatus.color)
                            }
                        }
                    }
                    .padding()
                    .background(Color("BrandNavy"))
                    .cornerRadius(12)
                }
                
                // Note
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "info.circle")
                            .foregroundColor(.orange)
                        Text("Not in Database")
                            .font(.headline)
                    }
                    
                    Text("This code was not found in our medical code database. The information shown is based on what was extracted from the scanned document.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color.orange.opacity(0.1))
                .cornerRadius(12)
            }
            .padding()
        }
        .navigationTitle("Code Details")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Bills List View

struct BillsListView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var patientDataService: PatientDataService
    @State private var navigationPath = NavigationPath()
    
    var body: some View {
        NavigationStack(path: $navigationPath) {
            BillsListViewContent(navigationPath: $navigationPath)
                .navigationDestination(for: String.self) { claimId in
                    if let claim = patientDataService.claims.first(where: { $0.id == claimId }) {
                        BillMainView(claim: claim)
                            .environmentObject(patientDataService)
                            .environmentObject(appState)
                            .onAppear {
                                appState.clearNewBadge(for: claimId)
                            }
                    }
                }
        }
    }
}

struct BillsListViewContent: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var patientDataService: PatientDataService
    @Binding var navigationPath: NavigationPath
    
    @State private var showingAddOptions = false
    @State private var showingManualEntry = false
    @State private var showingScanner = false
    @State private var searchText = ""
    @State private var selectedStatusFilter: BillStatus? = nil
    @State private var expandedPatients: Set<String> = []
    @State private var isPlusBlinking = false
    
    // Group claims by patient, then by status
    private var claimsByPatientAndStatus: [(patient: Patient, statusGroups: [(status: BillStatus, claims: [Claim])])] {
        var result: [(patient: Patient, statusGroups: [(status: BillStatus, claims: [Claim])])] = []
        
        // Only show bills for the selected patient, or all if none selected
        let patients: [Patient]
        if let selectedId = appState.selectedPatientId,
           let selected = patientDataService.patients.first(where: { $0.id == selectedId }) {
            patients = [selected]
        } else {
            patients = patientDataService.patients
        }
        
        for patient in patients {
            var claims = patientDataService.claims(for: patient.id)
            
            // Apply search filter
            if !searchText.isEmpty {
                claims = claims.filter { claim in
                    claim.providerName?.localizedCaseInsensitiveContains(searchText) == true ||
                    claim.claimNumber?.localizedCaseInsensitiveContains(searchText) == true ||
                    claim.notes?.localizedCaseInsensitiveContains(searchText) == true
                }
            }
            
            // Apply status filter
            if let statusFilter = selectedStatusFilter {
                claims = claims.filter { $0.billStatus == statusFilter }
            }
            
            if !claims.isEmpty {
                // Group by status
                var statusGroups: [(status: BillStatus, claims: [Claim])] = []
                
                for status in BillStatus.allCases.sorted(by: { $0.sortOrder < $1.sortOrder }) {
                    let statusClaims = claims.filter { $0.billStatus == status }
                        .sorted { $0.serviceDate > $1.serviceDate }
                    if !statusClaims.isEmpty {
                        statusGroups.append((status, statusClaims))
                    }
                }
                
                if !statusGroups.isEmpty {
                    result.append((patient, statusGroups))
                }
            }
        }
        
        // Sort by patient name
        return result.sorted { $0.patient.fullName < $1.patient.fullName }
    }
    
    private var allClaims: [Claim] {
        claimsByPatientAndStatus.flatMap { $0.statusGroups.flatMap { $0.claims } }
    }
    
    // Status counts — scoped to selected patient
    private var statusCounts: [BillStatus: Int] {
        var counts: [BillStatus: Int] = [:]
        let claims: [Claim]
        if let selectedId = appState.selectedPatientId {
            claims = patientDataService.claims(for: selectedId)
        } else {
            claims = patientDataService.patients.flatMap { patientDataService.claims(for: $0.id) }
        }
        for status in BillStatus.allCases {
            counts[status] = claims.filter { $0.billStatus == status }.count
        }
        return counts
    }
    
    private var totalOutstanding: Double {
        allClaims.filter { $0.billStatus == .outstanding }
            .reduce(0) { $0 + ($1.patientResponsibility ?? $1.billedAmount) }
    }
    
    var body: some View {
        Group {
            if patientDataService.patients.isEmpty {
                noPatientState
            } else if allClaims.isEmpty && searchText.isEmpty && selectedStatusFilter == nil {
                emptyState
            } else {
                billsListContent
            }
        }
        .navigationTitle("Bills").brandToolbar(title: "Bills", showPatient: true)
        .searchable(text: $searchText, prompt: "Search bills")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if patientDataService.patients.isEmpty {
                    // Blinking camera to draw attention
                    Image(systemName: "camera.viewfinder")
                        .font(.title3)
                        .foregroundColor(.blue)
                        .opacity(isPlusBlinking ? 0.2 : 1.0)
                        .scaleEffect(isPlusBlinking ? 0.85 : 1.0)
                        .animation(
                            .easeInOut(duration: 0.8)
                            .repeatForever(autoreverses: true),
                            value: isPlusBlinking
                        )
                        .onAppear {
                            isPlusBlinking = true
                        }
                        .onDisappear {
                            isPlusBlinking = false
                        }
                } else {
                    Menu {
                        Button {
                            showingManualEntry = true
                        } label: {
                            Label("Manual Entry", systemImage: "square.and.pencil")
                        }
                        
                        Button {
                            showingScanner = true
                        } label: {
                            Label("Scan Bill", systemImage: "camera.viewfinder")
                        }
                    } label: {
                        Image(systemName: "camera.viewfinder")
                            .font(.title3)
                    }
                }
            }
        }
        .sheet(isPresented: $showingManualEntry) {
            AddClaimView()
                .environmentObject(patientDataService)
                .environmentObject(appState)
        }
        .sheet(isPresented: $showingScanner) {
            BillScannerView()
                .environmentObject(patientDataService)
                .environmentObject(appState)
        }
    }
    
    private var billsListContent: some View {
        List {
            // Status Filter Bar
            Section {
                statusFilterBar
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            
            // Summary Section
            if !allClaims.isEmpty {
                Section {
                    summaryCard
                }
            }
            
            // Bills grouped by patient
            ForEach(claimsByPatientAndStatus, id: \.patient.id) { patientGroup in
                Section {
                    // Patient header with expand/collapse
                    PatientBillHeader(
                        patient: patientGroup.patient,
                        statusGroups: patientGroup.statusGroups,
                        isExpanded: expandedPatients.contains(patientGroup.patient.id)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            if expandedPatients.contains(patientGroup.patient.id) {
                                expandedPatients.remove(patientGroup.patient.id)
                            } else {
                                expandedPatients.insert(patientGroup.patient.id)
                            }
                        }
                    }
                    
                    // Bills by status (when expanded)
                    if expandedPatients.contains(patientGroup.patient.id) {
                        ForEach(patientGroup.statusGroups, id: \.status) { statusGroup in
                            // Status subheader
                            BillStatusSubheader(status: statusGroup.status, count: statusGroup.claims.count)
                            
                            // Claims in this status
                            ForEach(statusGroup.claims) { claim in
                                NavigationLink(value: claim.id) {
                                    BillRow(claim: claim)
                                }
                            }
                            .onDelete { offsets in
                                deleteClaims(at: offsets, from: statusGroup.claims)
                            }
                        }
                    }
                }
            }
            
            // No results message
            if claimsByPatientAndStatus.isEmpty && (!searchText.isEmpty || selectedStatusFilter != nil) {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        if let filter = selectedStatusFilter {
                            Text("No \(filter.rawValue.lowercased()) bills found")
                                .foregroundColor(.secondary)
                        } else {
                            Text("No bills found for \"\(searchText)\"")
                                .foregroundColor(.secondary)
                        }
                        
                        if selectedStatusFilter != nil {
                            Button("Clear Filter") {
                                selectedStatusFilter = nil
                            }
                            .font(.callout)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                }
            }
        }
        .listStyle(.insetGrouped)
        .onAppear {
            // Auto-expand all patients on first load
            if expandedPatients.isEmpty {
                expandedPatients = Set(patientDataService.patients.map { $0.id })
            }
            // Auto-expand the patient section containing the newly saved claim
            autoExpandForNewClaim()
        }
        .onChange(of: appState.lastSavedClaimId) { _, _ in
            autoExpandForNewClaim()
        }
    }
    
    /// Find which patient owns the newly saved claim and expand their section
    private func autoExpandForNewClaim() {
        guard let claimId = appState.lastSavedClaimId else { return }
        if let claim = patientDataService.claims.first(where: { $0.id == claimId }) {
            withAnimation(.easeInOut(duration: 0.3)) {
                expandedPatients.insert(claim.patientId)
                // Clear any status filter so the new claim is visible
                selectedStatusFilter = nil
            }
        }
    }
    
    // MARK: - Status Filter Bar
    
    private var statusFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                // All filter
                StatusFilterChip(
                    title: "All",
                    count: statusCounts.values.reduce(0, +),
                    color: .accentColor,
                    isSelected: selectedStatusFilter == nil
                ) {
                    withAnimation { selectedStatusFilter = nil }
                }
                
                // Status filters
                ForEach(BillStatus.allCases.sorted(by: { $0.sortOrder < $1.sortOrder }), id: \.self) { status in
                    StatusFilterChip(
                        title: status.rawValue,
                        count: statusCounts[status] ?? 0,
                        color: status.color,
                        isSelected: selectedStatusFilter == status
                    ) {
                        withAnimation {
                            selectedStatusFilter = selectedStatusFilter == status ? nil : status
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }
    
    // MARK: - Summary Card
    
    private var summaryCard: some View {
        HStack(spacing: 16) {
            // Total bills
            VStack(alignment: .leading, spacing: 4) {
                Text("Total Bills")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("\(allClaims.count)")
                    .font(.title2)
                    .fontWeight(.bold)
            }
            
            Divider()
                .frame(height: 40)
            
            // By status
            ForEach(BillStatus.allCases.sorted(by: { $0.sortOrder < $1.sortOrder }), id: \.self) { status in
                let count = allClaims.filter { $0.billStatus == status }.count
                if count > 0 {
                    VStack(alignment: .center, spacing: 4) {
                        Image(systemName: status.icon)
                            .foregroundColor(status.color)
                            .font(.caption)
                        Text("\(count)")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                    .frame(minWidth: 40)
                }
            }
            
            Spacer()
            
            // Outstanding amount
            VStack(alignment: .trailing, spacing: 4) {
                Text("Outstanding")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(totalOutstanding, format: .currency(code: "USD"))
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(totalOutstanding > 0 ? .red : .green)
            }
        }
        .padding(.vertical, 8)
    }
    
    private var noPatientState: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 70))
                .foregroundStyle(.blue, .blue.opacity(0.3))
                .symbolEffect(.pulse, options: .repeating)
            
            Text("Add a Patient First")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("You need at least one patient before you can start tracking bills.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
            
            VStack(spacing: 14) {
                // Option 1: Go to Patients tab
                Button {
                    appState.selectedTab = 2 // Patients tab
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "person.badge.plus")
                            .font(.title3)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Add Patient Manually")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Text("Go to the Patients tab")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.8))
                        }
                        Spacer()
                        Image(systemName: "arrow.right")
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color("BrandCyan"))
                    )
                }
                
                // Option 2: Scan a bill
                Button {
                    showingScanner = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "camera.viewfinder")
                            .font(.title3)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Scan a Bill")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Text("Patient name extracted from scan")
                                .font(.caption)
                                .foregroundColor(.accentColor.opacity(0.8))
                        }
                        Spacer()
                        Image(systemName: "arrow.right")
                    }
                    .foregroundColor(.accentColor)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.accentColor, lineWidth: 1.5)
                    )
                }
            }
            .padding(.horizontal, 30)
            .padding(.top, 8)
            
            Spacer()
            Spacer()
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("No Bills Yet")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Add a bill manually or scan one with your camera.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            // Two buttons for empty state
            HStack(spacing: 16) {
                Button {
                    showingManualEntry = true
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "square.and.pencil")
                            .font(.title2)
                        Text("Manual")
                            .font(.caption)
                    }
                    .frame(width: 80, height: 70)
                }
                .buttonStyle(.bordered)
                
                Button {
                    showingScanner = true
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "camera.viewfinder")
                            .font(.title2)
                        Text("Scan")
                            .font(.caption)
                    }
                    .frame(width: 80, height: 70)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.top, 10)
            
            // Quick Actions
            if let patientId = appState.selectedPatientId {
                Divider()
                    .padding(.horizontal, 40)
                
                Text("Quick Actions")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 12) {
                    QuickActionButton(
                        icon: "shield.lefthalf.filled",
                        title: "Insurance",
                        count: patientDataService.policies(for: patientId).count,
                        color: .blue,
                        destination: AnyView(
                            InsuranceListView(patientId: patientId)
                                .environmentObject(patientDataService)
                                .environmentObject(appState)
                        )
                    )
                    
                    QuickActionButton(
                        icon: "calendar.badge.clock",
                        title: "Visits",
                        count: patientDataService.visits(for: patientId).count,
                        color: .purple,
                        destination: AnyView(
                            VisitListView(patientId: patientId)
                                .environmentObject(patientDataService)
                                .environmentObject(appState)
                        )
                    )
                    
                    QuickActionButton(
                        icon: "creditcard",
                        title: "Payments",
                        count: patientDataService.paymentMethods(for: patientId).count,
                        color: .green,
                        destination: AnyView(
                            PaymentMethodListView(patientId: patientId)
                                .environmentObject(patientDataService)
                        )
                    )
                }
                .padding(.horizontal, 20)
            }
        }
    }
    
    private func deleteClaims(at offsets: IndexSet, from claims: [Claim]) {
        for index in offsets {
            let claim = claims[index]
            patientDataService.deleteClaim(claim)
        }
    }
}

// MARK: - Quick Action Button

struct QuickActionButton: View {
    let icon: String
    let title: String
    let count: Int
    let color: Color
    let destination: AnyView
    
    var body: some View {
        NavigationLink {
            destination
        } label: {
            VStack(spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: icon)
                        .font(.title2)
                        .foregroundColor(color)
                        .frame(width: 44, height: 44)
                        .background(
                            Circle()
                                .fill(color.opacity(0.1))
                        )
                    
                    if count > 0 {
                        Text("\(count)")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .frame(minWidth: 16, minHeight: 16)
                            .background(Circle().fill(color))
                            .offset(x: 4, y: -4)
                    }
                }
                
                Text(title)
                    .font(.caption)
                    .foregroundColor(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color("BrandNavy"))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Status Filter Chip

struct StatusFilterChip: View {
    let title: String
    let count: Int
    let color: Color
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .semibold : .regular)
                
                Text("\(count)")
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(isSelected ? Color.white.opacity(0.3) : color.opacity(0.2))
                    )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(isSelected ? color : Color("BrandNavy"))
            )
            .foregroundColor(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Patient Bill Header

struct PatientBillHeader: View {
    let patient: Patient
    let statusGroups: [(status: BillStatus, claims: [Claim])]
    let isExpanded: Bool
    
    private var totalClaims: Int {
        statusGroups.reduce(0) { $0 + $1.claims.count }
    }
    
    private var totalOutstanding: Double {
        var total: Double = 0
        for group in statusGroups {
            for claim in group.claims {
                if claim.billStatus == .outstanding {
                    total += claim.patientResponsibility ?? claim.billedAmount
                }
            }
        }
        return total
    }
    
    var body: some View {
        HStack(spacing: 12) {
            chevronView
            avatarView
            nameAndStatusView
            Spacer()
            if totalOutstanding > 0 {
                outstandingView
            }
        }
        .padding(.vertical, 8)
    }
    
    private var chevronView: some View {
        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
            .font(.caption)
            .foregroundColor(.secondary)
            .frame(width: 16)
    }
    
    private var avatarView: some View {
        ZStack {
            Circle()
                .fill(Color.accentColor.opacity(0.2))
                .frame(width: 40, height: 40)
            
            Text(patient.initials)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.accentColor)
        }
    }
    
    private var nameAndStatusView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(patient.fullName)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            
            statusBadgesView
        }
    }
    
    private var statusBadgesView: some View {
        HStack(spacing: 8) {
            ForEach(statusGroups, id: \.status) { group in
                StatusBadgeItem(status: group.status, count: group.claims.count)
            }
        }
    }
    
    private var outstandingView: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text("Owed")
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(totalOutstanding, format: .currency(code: "USD"))
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.red)
        }
    }
}

// MARK: - Status Badge Item

struct StatusBadgeItem: View {
    let status: BillStatus
    let count: Int
    
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: status.icon)
                .font(.caption2)
            Text("\(count)")
                .font(.caption2)
                .fontWeight(.medium)
        }
        .foregroundColor(status.color)
    }
}

// MARK: - Bill Status Subheader

struct BillStatusSubheader: View {
    let status: BillStatus
    let count: Int
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: status.icon)
                .foregroundColor(status.color)
            
            Text(status.rawValue)
                .font(.subheadline)
                .fontWeight(.medium)
            
            Text("(\(count))")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
        }
        .padding(.leading, 0)
        .padding(.vertical, 4)
        .listRowBackground(status.color.opacity(0.08))
    }
}

// MARK: - Bill Row

struct BillRow: View {
    let claim: Claim
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Status icon
            Image(systemName: claim.billStatus.icon)
                .foregroundColor(claim.billStatus.color)
                .font(.title3)
                .frame(width: 24, alignment: .center)
            
            // Bill info
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(claim.providerName ?? "Unknown Provider")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    
                    if appState.isNewlySaved(claimId: claim.id) {
                        Text("NEW")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.red))
                    }
                }
                
                HStack(spacing: 4) {
                    Text(claim.serviceDate, format: .dateTime.month(.abbreviated).day().year(.twoDigits))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if let codes = claim.procedureCodes, !codes.isEmpty {
                        Text("·").foregroundColor(.secondary.opacity(0.5))
                        Text("\(codes.count) code\(codes.count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("·").foregroundColor(.secondary.opacity(0.5))
                        Text("No codes")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
            }
            
            Spacer(minLength: 4)
            
            // Amount
            VStack(alignment: .trailing, spacing: 2) {
                Text(claim.patientResponsibility ?? claim.billedAmount, format: .currency(code: "USD"))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .foregroundColor(claim.billStatus == .resolved ? .green : .primary)
                
                if claim.billStatus == .resolved {
                    Text("Paid")
                        .font(.caption2)
                        .foregroundColor(.green)
                }
            }
        }
        .padding(.vertical, 6)
        .listRowBackground(
            appState.isNewlySaved(claimId: claim.id)
                ? Color.accentColor.opacity(0.08)
                : Color("BrandDeepNavy")
        )
    }
}

// MARK: - Add Claim View

struct AddClaimView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var patientDataService: PatientDataService
    @EnvironmentObject var appState: AppState
    
    @State private var providerName = ""
    @State private var serviceDate = Date()
    @State private var billedAmount = ""
    @State private var claimNumber = ""
    @State private var notes = ""
    
    // Duplicate detection
    @State private var showingDuplicateAlert = false
    @State private var duplicateClaim: Claim?
    @State private var pendingClaim: Claim?
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Service Details") {
                    TextField("Provider Name", text: $providerName)
                    DatePicker("Date of Service", selection: $serviceDate, displayedComponents: .date)
                    TextField("Claim/Bill Number (optional)", text: $claimNumber)
                }
                
                Section("Amount") {
                    HStack {
                        Text("$")
                        TextField("0.00", text: $billedAmount)
                            .keyboardType(.decimalPad)
                    }
                }
                
                Section("Notes") {
                    TextField("Optional notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Add Bill")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveClaim()
                    }
                    .disabled(providerName.isEmpty || billedAmount.isEmpty)
                }
            }
            .alert("Existing Bill Found", isPresented: $showingDuplicateAlert) {
                Button("Replace Existing", role: .destructive) {
                    replaceExistingClaim()
                }
                Button("Keep Both") {
                    saveAsNewClaim()
                }
                Button("Cancel", role: .cancel) {
                    pendingClaim = nil
                }
            } message: {
                if let dup = duplicateClaim {
                    let dateStr = dup.serviceDate.formatted(date: .abbreviated, time: .omitted)
                    let amtStr = String(format: "$%.2f", dup.billedAmount)
                    Text("A bill from \(dup.providerName ?? "this provider") dated \(dateStr) for \(amtStr) already exists.\n\nReplace it with this entry, or keep both?")
                } else {
                    Text("A similar bill already exists.")
                }
            }
        }
    }
    
    private func saveClaim() {
        guard let patientId = appState.selectedPatientId,
              let amount = Double(billedAmount) else { return }
        
        let claim = Claim(
            patientId: patientId,
            policyId: "",
            providerName: providerName,
            claimNumber: claimNumber.isEmpty ? nil : claimNumber,
            status: .notSubmitted,
            serviceDate: serviceDate,
            billedAmount: amount,
            patientResponsibility: amount,
            notes: notes.isEmpty ? nil : notes,
            createdAt: Date(),
            updatedAt: Date()
        )
        
        // Check for duplicate
        if let existing = patientDataService.findDuplicateClaim(
            patientId: patientId,
            providerName: providerName,
            claimNumber: claimNumber.isEmpty ? nil : claimNumber,
            serviceDate: serviceDate,
            billedAmount: amount
        ) {
            duplicateClaim = existing
            pendingClaim = claim
            showingDuplicateAlert = true
        } else {
            patientDataService.saveClaim(claim)
            appState.navigateToSavedBill(claimId: claim.id)
            dismiss()
        }
    }
    
    private func replaceExistingClaim() {
        guard var claim = pendingClaim, let existing = duplicateClaim else { return }
        
        // Preserve progress from old claim
        if existing.status != .notSubmitted && claim.status == .notSubmitted {
            claim.status = existing.status
            claim.statusHistory = existing.statusHistory
        }
        if !existing.insurancePayments.isEmpty && claim.insurancePayments.isEmpty {
            claim.insurancePayments = existing.insurancePayments
        }
        if claim.paidAmount == nil { claim.paidAmount = existing.paidAmount }
        if claim.allowedAmount == nil { claim.allowedAmount = existing.allowedAmount }
        
        claim.id = existing.id
        claim.createdAt = existing.createdAt
        claim.updatedAt = Date()
        
        patientDataService.saveClaim(claim)
        appState.navigateToSavedBill(claimId: claim.id)
        
        duplicateClaim = nil
        pendingClaim = nil
        dismiss()
    }
    
    private func saveAsNewClaim() {
        guard let claim = pendingClaim else { return }
        
        patientDataService.saveClaim(claim)
        appState.navigateToSavedBill(claimId: claim.id)
        
        duplicateClaim = nil
        pendingClaim = nil
        dismiss()
    }
}

// MARK: - Claim Row

struct ClaimRow: View {
    let claim: Claim
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(claim.providerName ?? "Medical Bill")
                    .font(.headline)
                Spacer()
                StatusBadge(status: claim.status)
            }
            
            HStack {
                Text(claim.serviceDate, style: .date)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                if let claimNumber = claim.claimNumber {
                    Text("•")
                        .foregroundColor(.secondary)
                    Text("#\(claimNumber)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            
            HStack {
                Text("Billed:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(claim.billedAmount, format: .currency(code: "USD"))
                    .font(.caption)
                
                if let amount = claim.patientResponsibility, amount > 0 {
                    Spacer()
                    Text("You owe:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(amount, format: .currency(code: "USD"))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.orange)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Status Badge

struct StatusBadge: View {
    let status: ClaimStatus
    
    var body: some View {
        Text(status.rawValue)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(statusColor.opacity(0.2))
            .foregroundColor(statusColor)
            .cornerRadius(6)
    }
    
    private var statusColor: Color {
        switch status {
        case .notSubmitted: return .gray
        case .submitted, .pending, .inReview: return .blue
        case .approved, .partiallyApproved, .paid: return .green
        case .denied: return .red
        case .appealed: return .orange
        case .closed: return .gray
        }
    }
}

// MARK: - Profile View

struct ProfileView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var userManager: UserManager
    @EnvironmentObject var patientDataService: PatientDataService
    
    @State private var showingAddPatient = false
    
    var body: some View {
        NavigationStack {
            List {
                // User Info Section
                Section {
                    if let user = userManager.currentUser {
                        HStack(spacing: 16) {
                            ZStack {
                                Circle()
                                    .fill(Color.accentColor)
                                    .frame(width: 60, height: 60)
                                
                                Text(user.displayName.prefix(2).uppercased())
                                    .font(.title2)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(user.displayName)
                                    .font(.headline)
                                Text(user.email)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
                
                // Patients Section
                Section("My Patients") {
                    ForEach(patientDataService.patients) { patient in
                        PatientRow(
                            patient: patient,
                            isSelected: patient.id == appState.selectedPatientId
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            appState.selectPatient(patient.id)
                        }
                    }
                    .onDelete(perform: deletePatients)
                    
                    Button {
                        showingAddPatient = true
                    } label: {
                        Label("Add Patient", systemImage: "person.badge.plus")
                    }
                }
                
                // Quick Stats
                Section("Summary") {
                    if let patientId = appState.selectedPatientId {
                        let balance = patientDataService.totalOutstandingBalance(for: patientId)
                        HStack {
                            Text("Outstanding Balance")
                            Spacer()
                            Text(balance, format: .currency(code: "USD"))
                                .fontWeight(.semibold)
                                .foregroundColor(balance > 0 ? .red : .green)
                        }
                        
                        HStack {
                            Text("Total Claims")
                            Spacer()
                            Text("\(patientDataService.claims(for: patientId).count)")
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Text("Select a patient to see summary")
                            .foregroundColor(.secondary)
                    }
                }
                
                // Healthcare Providers Section
                Section("Healthcare Providers") {
                    NavigationLink {
                        ProviderListViewContent()
                            .environmentObject(patientDataService)
                    } label: {
                        HStack {
                            Label("My Providers", systemImage: "building.2.fill")
                            Spacer()
                            Text("\(patientDataService.providers.count)")
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    NavigationLink {
                        ProviderMapView(providers: patientDataService.providers)
                    } label: {
                        Label("Provider Map", systemImage: "map.fill")
                    }
                    .disabled(patientDataService.providers.isEmpty)
                }
                
                // Settings Section
                Section("Settings") {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Label("Preferences", systemImage: "gear")
                    }
                    
                    NavigationLink {
                        InfoView()
                    } label: {
                        Label("About BillGuard", systemImage: "info.circle")
                    }
                }
                
                // Sign Out
                Section {
                    Button(role: .destructive) {
                        appState.logout()
                    } label: {
                        HStack {
                            Spacer()
                            Text("Sign Out")
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("Profile")
            .sheet(isPresented: $showingAddPatient) {
                AddPatientView()
                    .environmentObject(patientDataService)
                    .environmentObject(appState)
            }
        }
    }
    
    private func deletePatients(at offsets: IndexSet) {
        for index in offsets {
            let patient = patientDataService.patients[index]
            // If deleting selected patient, clear selection
            if patient.id == appState.selectedPatientId {
                appState.selectedPatientId = nil
            }
            patientDataService.deletePatient(patient)
        }
    }
}

// MARK: - Patient List View

struct PatientListView: View {
    var body: some View {
        NavigationStack {
            PatientListViewContent()
        }
    }
}

struct PatientListViewContent: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var patientDataService: PatientDataService
    
    @State private var showingAddPatient = false
    @State private var searchText = ""
    @State private var showingDeleteAlert = false
    @State private var patientToDelete: Patient?
    
    var filteredPatients: [Patient] {
        if searchText.isEmpty {
            return patientDataService.patients
        }
        return patientDataService.patients.filter {
            $0.fullName.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        Group {
            if patientDataService.patients.isEmpty {
                emptyStateView
            } else {
                patientListContent
            }
        }
        .navigationTitle("Patients").brandToolbar(title: "Patients", showPatient: true)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddPatient = true
                } label: {
                    Image(systemName: "person.badge.plus")
                }
            }
        }
        .sheet(isPresented: $showingAddPatient) {
            AddPatientView()
                .environmentObject(patientDataService)
                .environmentObject(appState)
        }
        .alert("Delete Patient", isPresented: $showingDeleteAlert, presenting: patientToDelete) { patient in
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                deletePatient(patient)
            }
        } message: { patient in
            Text("Are you sure you want to delete \(patient.fullName)? This will also delete all their bills and claims.")
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: "person.2.slash")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text("No Patients")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Add a patient to start tracking medical bills and procedures.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Button {
                showingAddPatient = true
            } label: {
                Label("Add First Patient", systemImage: "person.badge.plus")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.accentColor)
                    .cornerRadius(10)
            }
            .padding(.top, 10)
            
            Spacer()
        }
    }
    
    private var patientListContent: some View {
        List {
            // Currently Selected Patient
            if let selectedId = appState.selectedPatientId,
               let selectedPatient = patientDataService.patients.first(where: { $0.id == selectedId }) {
                Section {
                    PatientDetailRow(patient: selectedPatient, isSelected: true)
                } header: {
                    HStack {
                        Text("Active Patient")
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                    }
                }
            }
            
            // All Patients
            Section {
                ForEach(filteredPatients) { patient in
                    PatientDetailRow(
                        patient: patient,
                        isSelected: patient.id == appState.selectedPatientId
                    )
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            patientToDelete = patient
                            showingDeleteAlert = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            } header: {
                HStack {
                    Text("All Patients")
                    Spacer()
                    Text("\(patientDataService.patients.count)")
                        .foregroundColor(.secondary)
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search patients")
    }
    
    private func deletePatient(_ patient: Patient) {
        // If deleting selected patient, clear selection
        if patient.id == appState.selectedPatientId {
            appState.selectedPatientId = nil
        }
        patientDataService.deletePatient(patient)
    }
}

// MARK: - Patient Detail Row

struct PatientDetailRow: View {
    let patient: Patient
    let isSelected: Bool
    @EnvironmentObject var patientDataService: PatientDataService
    
    private var documentCount: Int {
        patientDataService.documents(for: patient.id).count
    }
    
    private var claimCount: Int {
        patientDataService.claims(for: patient.id).count
    }
    
    private var dobFormatted: String? {
        guard let dob = patient.dateOfBirth else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: dob)
    }
    
    var body: some View {
        NavigationLink(destination: PatientInfoView(patient: patient)) {
            HStack(spacing: 12) {
                // Avatar
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.accentColor : Color(.systemGray4))
                        .frame(width: 50, height: 50)
                    
                    Text(patient.initials)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(isSelected ? .white : .primary)
                }
                
                // Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(patient.fullName)
                        .font(.headline)
                        .lineLimit(1)
                    
                    HStack(spacing: 8) {
                        if let dob = dobFormatted {
                            HStack(spacing: 4) {
                                Image(systemName: "calendar")
                                Text(dob)
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                        }
                        
                        if claimCount > 0 {
                            HStack(spacing: 4) {
                                Image(systemName: "doc.text")
                                Text("\(claimCount) bills")
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                        }
                        
                        if documentCount > 0 {
                            HStack(spacing: 4) {
                                Image(systemName: "folder")
                                Text("\(documentCount) docs")
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                        }
                    }
                }
                
                Spacer()
                
                // Selection indicator
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.accentColor)
                        .font(.title3)
                }
            }
            .padding(.vertical, 6)
        }
    }
}

// MARK: - Patient Info View

struct PatientInfoView: View {
    @EnvironmentObject var patientDataService: PatientDataService
    @EnvironmentObject var appState: AppState
    
    let patient: Patient
    @State private var showingEdit = false
    
    /// Re-fetch patient from data service so edits are reflected
    private var currentPatient: Patient {
        patientDataService.patients.first(where: { $0.id == patient.id }) ?? patient
    }
    
    private var claimCount: Int {
        patientDataService.claims(for: patient.id).count
    }
    
    private var documentCount: Int {
        patientDataService.documents(for: patient.id).count
    }
    
    private var insuranceCount: Int {
        patientDataService.policies(for: patient.id).count
    }
    
    private var visitCount: Int {
        patientDataService.visits(for: patient.id).count
    }
    
    private var paymentMethodCount: Int {
        patientDataService.paymentMethods(for: patient.id).count
    }
    
    private var dobString: String? {
        guard let dob = currentPatient.dateOfBirth else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: dob)
    }
    
    var body: some View {
        List {
            basicInfoSection
            contactSection
            addressSection
            managementSection
            documentsSection
            actionsSection
        }
        .navigationTitle(currentPatient.fullName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") {
                    showingEdit = true
                }
            }
        }
        .sheet(isPresented: $showingEdit) {
            EditPatientView(patient: currentPatient)
                .environmentObject(patientDataService)
                .environmentObject(appState)
        }
        .onAppear {
            // Auto-select this patient when viewing their detail
            if appState.selectedPatientId != patient.id {
                appState.selectPatient(patient.id)
            }
        }
    }
    
    private var basicInfoSection: some View {
        Section(header: Text("Basic Information")) {
            HStack {
                Text("Name")
                Spacer()
                Text(currentPatient.fullName)
                    .foregroundColor(.secondary)
            }
            
            HStack {
                Text("Date of Birth")
                Spacer()
                Text(dobString ?? "Not set")
                    .foregroundColor(.secondary)
            }
            
            HStack {
                Text("Gender")
                Spacer()
                Text(currentPatient.gender?.rawValue ?? "Not set")
                    .foregroundColor(.secondary)
            }
            
            HStack {
                Text("Relationship")
                Spacer()
                Text(currentPatient.relationship.rawValue)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    @ViewBuilder
    private var contactSection: some View {
        if !currentPatient.phoneNumbers.isEmpty || !currentPatient.emailAddresses.isEmpty {
            Section(header: Text("Contact")) {
                ForEach(currentPatient.phoneNumbers) { phone in
                    HStack {
                        Text(phone.label.rawValue)
                        Spacer()
                        Text(phone.number)
                            .foregroundColor(.secondary)
                    }
                }
                
                ForEach(patient.emailAddresses) { email in
                    HStack {
                        Text(email.label.rawValue)
                        Spacer()
                        Text(email.address)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private var addressSection: some View {
        if !patient.addresses.isEmpty {
            Section(header: Text("Address")) {
                ForEach(patient.addresses) { address in
                    VStack(alignment: .leading, spacing: 4) {
                        if !address.street1.isEmpty {
                            Text(address.street1)
                        }
                        if let street2 = address.street2, !street2.isEmpty {
                            Text(street2)
                        }
                        HStack(spacing: 0) {
                            Text(address.city)
                            if !address.state.isEmpty {
                                Text(", \(address.state) ")
                            }
                            Text(address.zipCode)
                        }
                    }
                    .foregroundColor(.secondary)
                }
            }
        }
    }
    
    private var managementSection: some View {
        Section(header: Text("Management")) {
            // Bills
            NavigationLink {
                BillsListView()
                    .environmentObject(patientDataService)
                    .environmentObject(appState)
            } label: {
                HStack {
                    Label("Bills", systemImage: "doc.text")
                    Spacer()
                    Text("\(claimCount)")
                        .foregroundColor(.secondary)
                }
            }
            
            // Insurance
            NavigationLink {
                InsuranceListView(patientId: patient.id)
                    .environmentObject(patientDataService)
                    .environmentObject(appState)
            } label: {
                HStack {
                    Label("Insurance", systemImage: "shield.lefthalf.filled")
                    Spacer()
                    Text("\(insuranceCount)")
                        .foregroundColor(.secondary)
                }
            }
            
            // Visits
            NavigationLink {
                VisitListView(patientId: patient.id)
                    .environmentObject(patientDataService)
                    .environmentObject(appState)
            } label: {
                HStack {
                    Label("Visits", systemImage: "calendar.badge.clock")
                    Spacer()
                    Text("\(visitCount)")
                        .foregroundColor(.secondary)
                }
            }
            
            // Payment Methods
            NavigationLink {
                PaymentMethodListView(patientId: patient.id)
                    .environmentObject(patientDataService)
            } label: {
                HStack {
                    Label("Payment Methods", systemImage: "creditcard")
                    Spacer()
                    Text("\(paymentMethodCount)")
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    private var documentsSection: some View {
        Section(footer: Text("Store EOBs, statements, insurance cards, and other medical documents")) {
            NavigationLink(destination: PatientDocumentsView(patientId: patient.id)) {
                HStack {
                    Label("Other Documents", systemImage: "folder")
                    Spacer()
                    Text("\(documentCount)")
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    private var actionsSection: some View {
        Section {
            Button {
                appState.selectPatient(patient.id)
            } label: {
                Label("Set as Active Patient", systemImage: "checkmark.circle")
            }
            .disabled(patient.id == appState.selectedPatientId)
        }
    }
}

// MARK: - Add Patient View

struct AddPatientView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var patientDataService: PatientDataService
    @EnvironmentObject var appState: AppState
    
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var dateOfBirth = Date()
    @State private var gender: Gender = .preferNotToSay
    @State private var phone = ""
    @State private var email = ""
    
    // Account info
    @State private var accountNumber = ""
    @State private var notes = ""
    
    // Address (optional)
    @State private var street1 = ""
    @State private var city = ""
    @State private var state = ""
    @State private var zipCode = ""
    
    @State private var showingScanner = false
    
    var body: some View {
        NavigationStack {
            Form {
                // Scan Button Section
                Section {
                    Button {
                        showingScanner = true
                    } label: {
                        HStack {
                            Image(systemName: "doc.text.viewfinder")
                                .font(.title2)
                                .foregroundColor(.accentColor)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Scan Patient Info")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                Text("Auto-fill from ID, insurance card, or document")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
                
                Section("Name") {
                    TextField("First Name", text: $firstName)
                        .textContentType(.givenName)
                    TextField("Last Name", text: $lastName)
                        .textContentType(.familyName)
                }
                
                Section("Account Info (Optional)") {
                    TextField("Account / Member ID", text: $accountNumber)
                        .textContentType(.creditCardNumber)
                    
                    VStack(alignment: .leading) {
                        Text("Notes")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextEditor(text: $notes)
                            .frame(minHeight: 80)
                    }
                }
                
                Section("Personal Info") {
                    DatePicker("Date of Birth", selection: $dateOfBirth, displayedComponents: .date)
                    
                    Picker("Gender", selection: $gender) {
                        ForEach(Gender.allCases, id: \.self) { gender in
                            Text(gender.rawValue).tag(gender)
                        }
                    }
                }
                
                Section("Contact (Optional)") {
                    TextField("Phone", text: $phone)
                        .textContentType(.telephoneNumber)
                        .keyboardType(.phonePad)
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                }
                
                Section("Address (Optional)") {
                    TextField("Street Address", text: $street1)
                        .textContentType(.streetAddressLine1)
                    TextField("City", text: $city)
                        .textContentType(.addressCity)
                    TextField("State", text: $state)
                        .textContentType(.addressState)
                    TextField("ZIP Code", text: $zipCode)
                        .textContentType(.postalCode)
                        .keyboardType(.numberPad)
                }
            }
            .navigationTitle("Add Patient")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        savePatient()
                    }
                    .disabled(firstName.isEmpty || lastName.isEmpty)
                }
            }
            .sheet(isPresented: $showingScanner) {
                ContactInfoScannerView(mode: .patient) { info in
                    applyScannedInfo(info)
                }
            }
        }
    }
    
    private func applyScannedInfo(_ info: ExtractedContactInfo) {
        if !info.firstName.isEmpty && firstName.isEmpty {
            firstName = info.firstName
        }
        if !info.lastName.isEmpty && lastName.isEmpty {
            lastName = info.lastName
        }
        if !info.accountNumber.isEmpty && accountNumber.isEmpty {
            accountNumber = info.accountNumber
        }
        
        // Build scanned notes from insurance, date of service, and any other notes
        var scannedNotes: [String] = []
        if !info.insurance.isEmpty {
            scannedNotes.append("Insurance: \(info.insurance)")
        }
        if !info.dateOfService.isEmpty {
            scannedNotes.append("Date of Service: \(info.dateOfService)")
        }
        if !info.notes.isEmpty {
            scannedNotes.append(info.notes)
        }
        
        if !scannedNotes.isEmpty {
            let newNotes = scannedNotes.joined(separator: "\n")
            if notes.isEmpty {
                notes = newNotes
            } else {
                notes += "\n\n" + newNotes
            }
        }
        
        if !info.phone.isEmpty && phone.isEmpty {
            phone = info.phone
        }
        if !info.email.isEmpty && email.isEmpty {
            email = info.email
        }
        if !info.address.isEmpty && street1.isEmpty {
            street1 = info.address
        }
        if !info.city.isEmpty && city.isEmpty {
            city = info.city
        }
        if !info.state.isEmpty && state.isEmpty {
            state = info.state
        }
        if !info.zipCode.isEmpty && zipCode.isEmpty {
            zipCode = info.zipCode
        }
        
        // Try to parse date of birth
        if !info.dateOfBirth.isEmpty {
            let dateFormatter = DateFormatter()
            let formats = ["MM/dd/yyyy", "M/d/yyyy", "MM-dd-yyyy", "M-d-yyyy", "MM/dd/yy", "M/d/yy"]
            for format in formats {
                dateFormatter.dateFormat = format
                if let date = dateFormatter.date(from: info.dateOfBirth) {
                    dateOfBirth = date
                    break
                }
            }
        }
    }
    
    private func savePatient() {
        var phones: [PatientPhone] = []
        if !phone.isEmpty {
            phones.append(PatientPhone(label: .mobile, number: phone, isPrimary: true))
        }
        
        var emails: [PatientEmail] = []
        if !email.isEmpty {
            emails.append(PatientEmail(label: .personal, address: email, isPrimary: true))
        }
        
        var addresses: [PatientAddress] = []
        if !street1.isEmpty || !city.isEmpty {
            addresses.append(PatientAddress(
                label: .home,
                street1: street1,
                street2: nil,
                city: city,
                state: state,
                zipCode: zipCode,
                isPrimary: true
            ))
        }
        
        // Combine account number and notes
        var combinedNotes = ""
        if !accountNumber.isEmpty {
            combinedNotes = "Account #: \(accountNumber)"
        }
        if !notes.isEmpty {
            if !combinedNotes.isEmpty {
                combinedNotes += "\n\n"
            }
            combinedNotes += notes
        }
        
        let patient = Patient(
            firstName: firstName,
            lastName: lastName,
            dateOfBirth: dateOfBirth,
            gender: gender,
            addresses: addresses,
            phoneNumbers: phones,
            emailAddresses: emails,
            notes: combinedNotes.isEmpty ? nil : combinedNotes
        )
        
        patientDataService.savePatient(patient)
        
        // Auto-select the new patient
        appState.selectPatient(patient.id)
        
        dismiss()
    }
}

// MARK: - Edit Patient View

struct EditPatientView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var patientDataService: PatientDataService
    @EnvironmentObject var appState: AppState
    
    let patient: Patient
    
    @State private var firstName: String
    @State private var lastName: String
    @State private var middleName: String
    @State private var dateOfBirth: Date
    @State private var hasDOB: Bool
    @State private var gender: Gender
    @State private var relationship: PatientRelationship
    @State private var phone: String
    @State private var email: String
    @State private var notes: String
    
    // Address
    @State private var street1: String
    @State private var street2: String
    @State private var city: String
    @State private var state: String
    @State private var zipCode: String
    
    init(patient: Patient) {
        self.patient = patient
        _firstName = State(initialValue: patient.firstName)
        _lastName = State(initialValue: patient.lastName)
        _middleName = State(initialValue: patient.middleName ?? "")
        _dateOfBirth = State(initialValue: patient.dateOfBirth ?? Date())
        _hasDOB = State(initialValue: patient.dateOfBirth != nil)
        _gender = State(initialValue: patient.gender ?? .preferNotToSay)
        _relationship = State(initialValue: patient.relationship)
        _phone = State(initialValue: patient.phoneNumbers.first?.number ?? "")
        _email = State(initialValue: patient.emailAddresses.first?.address ?? "")
        _notes = State(initialValue: patient.notes ?? "")
        
        let addr = patient.addresses.first
        _street1 = State(initialValue: addr?.street1 ?? "")
        _street2 = State(initialValue: addr?.street2 ?? "")
        _city = State(initialValue: addr?.city ?? "")
        _state = State(initialValue: addr?.state ?? "")
        _zipCode = State(initialValue: addr?.zipCode ?? "")
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("First Name", text: $firstName)
                        .textContentType(.givenName)
                    TextField("Middle Name (Optional)", text: $middleName)
                        .textContentType(.middleName)
                    TextField("Last Name", text: $lastName)
                        .textContentType(.familyName)
                }
                
                Section("Personal Info") {
                    Toggle("Date of Birth", isOn: $hasDOB)
                    if hasDOB {
                        DatePicker("DOB", selection: $dateOfBirth, displayedComponents: .date)
                    }
                    
                    Picker("Gender", selection: $gender) {
                        ForEach(Gender.allCases, id: \.self) { g in
                            Text(g.rawValue).tag(g)
                        }
                    }
                    
                    Picker("Relationship", selection: $relationship) {
                        ForEach(PatientRelationship.allCases, id: \.self) { r in
                            Text(r.rawValue).tag(r)
                        }
                    }
                }
                
                Section("Contact") {
                    TextField("Phone", text: $phone)
                        .textContentType(.telephoneNumber)
                        .keyboardType(.phonePad)
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                }
                
                Section("Address") {
                    TextField("Street Address", text: $street1)
                        .textContentType(.streetAddressLine1)
                    TextField("Apt / Suite (Optional)", text: $street2)
                        .textContentType(.streetAddressLine2)
                    TextField("City", text: $city)
                        .textContentType(.addressCity)
                    TextField("State", text: $state)
                        .textContentType(.addressState)
                    TextField("ZIP Code", text: $zipCode)
                        .textContentType(.postalCode)
                        .keyboardType(.numberPad)
                }
                
                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 80)
                }
            }
            .navigationTitle("Edit Patient")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveChanges() }
                        .disabled(firstName.isEmpty || lastName.isEmpty)
                }
            }
        }
    }
    
    private func saveChanges() {
        var updated = patient
        updated.firstName = firstName
        updated.lastName = lastName
        updated.middleName = middleName.isEmpty ? nil : middleName
        updated.dateOfBirth = hasDOB ? dateOfBirth : nil
        updated.gender = gender
        updated.relationship = relationship
        updated.notes = notes.isEmpty ? nil : notes
        updated.updatedAt = Date()
        
        // Phone
        if !phone.isEmpty {
            if var existing = updated.phoneNumbers.first {
                existing.number = phone
                updated.phoneNumbers[0] = existing
            } else {
                updated.phoneNumbers = [PatientPhone(label: .mobile, number: phone, isPrimary: true)]
            }
        } else {
            updated.phoneNumbers = []
        }
        
        // Email
        if !email.isEmpty {
            if var existing = updated.emailAddresses.first {
                existing.address = email
                updated.emailAddresses[0] = existing
            } else {
                updated.emailAddresses = [PatientEmail(label: .personal, address: email, isPrimary: true)]
            }
        } else {
            updated.emailAddresses = []
        }
        
        // Address
        if !street1.isEmpty || !city.isEmpty {
            let addr = PatientAddress(
                id: patient.addresses.first?.id ?? UUID().uuidString,
                label: patient.addresses.first?.label ?? .home,
                street1: street1,
                street2: street2.isEmpty ? nil : street2,
                city: city,
                state: state,
                zipCode: zipCode,
                isPrimary: true
            )
            if updated.addresses.isEmpty {
                updated.addresses = [addr]
            } else {
                updated.addresses[0] = addr
            }
        }
        
        patientDataService.savePatient(updated)
        dismiss()
    }
}

// MARK: - Patient Row

struct PatientRow: View {
    let patient: Patient
    let isSelected: Bool
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(patient.fullName)
                    .font(.headline)
                if let dob = patient.dateOfBirth {
                    Text("DOB: \(dob, style: .date)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.accentColor)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var userManager: UserManager
    @EnvironmentObject var patientDataService: PatientDataService
    
    @State private var enableNotifications: Bool = true
    @State private var enableBiometric: Bool = false
    @State private var showPriceEstimates: Bool = true
    @State private var detectNearbyFacilities: Bool = LocationReminderService.shared.isGenericDetectionEnabled

    var body: some View {
        Form {
            Section("Notifications") {
                Toggle("Enable Notifications", isOn: $enableNotifications)
                    .onChange(of: enableNotifications) { _, newValue in
                        updatePreference(\.enableNotifications, value: newValue)
                    }
            }

            Section(header: Text("Front-Desk Coaching"),
                    footer: Text("When you arrive at a saved provider, BillGuard pops the questions to ask at the front desk. Turn this on to also detect nearby hospitals and pharmacies you haven't saved (uses more battery and may occasionally misfire).")) {
                Toggle("Detect nearby facilities", isOn: $detectNearbyFacilities)
                    .onChange(of: detectNearbyFacilities) { _, newValue in
                        LocationReminderService.shared.setGenericFacilityDetection(newValue)
                        if newValue { LocationReminderService.shared.requestAlwaysAuthorization() }
                    }
            }

            Section("Security") {
                Toggle("Face ID / Touch ID", isOn: $enableBiometric)
                    .onChange(of: enableBiometric) { _, newValue in
                        updatePreference(\.enableBiometricAuth, value: newValue)
                    }
                
                NavigationLink("Change Password") {
                    ChangePasswordView()
                }
            }
            
            Section("Display") {
                Toggle("Show Price Estimates", isOn: $showPriceEstimates)
                    .onChange(of: showPriceEstimates) { _, newValue in
                        updatePreference(\.showPriceEstimates, value: newValue)
                    }
            }
            
            // Debug Section - Remove in production
            Section("Debug") {
                Button("Reset App (Show Onboarding)") {
                    UserDefaults.standard.removeObject(forKey: "hasCompletedOnboarding")
                    UserDefaults.standard.removeObject(forKey: "isLoggedIn")
                    appState.hasCompletedOnboarding = false
                    appState.isLoggedIn = false
                }
                
                Button("Reset to Login Screen") {
                    appState.logout()
                }
                
                Button("Clear All Patient Data") {
                    patientDataService.resetAllData()
                }
                
                Text("Logged in: \(appState.isLoggedIn ? "Yes" : "No")")
                    .foregroundColor(.secondary)
                Text("Onboarding done: \(appState.hasCompletedOnboarding ? "Yes" : "No")")
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle("Settings").brandToolbar(title: "Settings")
        .onAppear {
            loadPreferences()
        }
    }
    
    private func loadPreferences() {
        if let prefs = userManager.currentUser?.preferences {
            enableNotifications = prefs.enableNotifications
            enableBiometric = prefs.enableBiometricAuth
            showPriceEstimates = prefs.showPriceEstimates
        }
    }
    
    private func updatePreference<T>(_ keyPath: WritableKeyPath<UserPreferences, T>, value: T) {
        guard var prefs = userManager.currentUser?.preferences else { return }
        prefs[keyPath: keyPath] = value
        userManager.updatePreferences(prefs)
    }
}

// MARK: - Change Password View

struct ChangePasswordView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var userManager: UserManager
    
    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var errorMessage: String?
    @State private var showSuccess = false
    
    var body: some View {
        Form {
            Section {
                SecureField("Current Password", text: $currentPassword)
                SecureField("New Password", text: $newPassword)
                SecureField("Confirm New Password", text: $confirmPassword)
            }
            
            if let error = errorMessage {
                Section {
                    Text(error)
                        .foregroundColor(.red)
                }
            }
            
            Section {
                Button("Update Password") {
                    changePassword()
                }
                .disabled(currentPassword.isEmpty || newPassword.isEmpty || newPassword != confirmPassword)
            }
        }
        .navigationTitle("Change Password")
        .alert("Password Updated", isPresented: $showSuccess) {
            Button("OK") {
                dismiss()
            }
        } message: {
            Text("Your password has been changed successfully.")
        }
    }
    
    private func changePassword() {
        errorMessage = nil
        
        guard newPassword == confirmPassword else {
            errorMessage = "New passwords do not match"
            return
        }
        
        let result = userManager.changePassword(currentPassword: currentPassword, newPassword: newPassword)
        
        switch result {
        case .success:
            showSuccess = true
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Scanner Hub View

struct ScannerHubView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var patientDataService: PatientDataService
    
    @State private var showingBillScanner = false
    @State private var showingCodeScanner = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: "viewfinder")
                            .font(.system(size: 50))
                            .foregroundColor(.accentColor)
                        
                        Text("What would you like to scan?")
                            .font(.title2)
                            .fontWeight(.semibold)
                    }
                    .padding(.top, 30)
                    
                    // Scan Options
                    VStack(spacing: 16) {
                        // Scan Bill Option
                        Button {
                            showingBillScanner = true
                        } label: {
                            ScanOptionCard(
                                icon: "doc.text.viewfinder",
                                title: "Scan Medical Bill",
                                description: "Capture patient info, provider details, and procedure codes from a bill",
                                color: .blue
                            )
                        }
                        .buttonStyle(.plain)
                        
                        // Scan Codes Option
                        Button {
                            showingCodeScanner = true
                        } label: {
                            ScanOptionCard(
                                icon: "barcode.viewfinder",
                                title: "Scan Medical Codes",
                                description: "Look up CPT, ICD-10, or HCPCS codes by scanning them",
                                color: .green
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal)
                    
                    // Tips Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Scanning Tips")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        VStack(spacing: 8) {
                            ScanTipRow(icon: "lightbulb.fill", text: "Use good lighting for best results")
                            ScanTipRow(icon: "hand.raised.fill", text: "Hold camera steady over the document")
                            ScanTipRow(icon: "rectangle.dashed", text: "Position boxes over the text areas")
                            ScanTipRow(icon: "doc.on.doc.fill", text: "You can import PDFs from email too")
                        }
                        .padding()
                        .background(Color("BrandNavy"))
                        .cornerRadius(12)
                        .padding(.horizontal)
                    }
                    .padding(.top, 20)
                    
                    Spacer()
                }
            }
            .navigationTitle("Scan")
            .sheet(isPresented: $showingBillScanner) {
                BillScannerView()
                    .environmentObject(patientDataService)
                    .environmentObject(appState)
            }
            .fullScreenCover(isPresented: $showingCodeScanner) {
                ScannerView(onDismiss: { showingCodeScanner = false })
                    .environmentObject(appState)
            }
        }
    }
}

// MARK: - Scan Option Card

struct ScanOptionCard: View {
    let icon: String
    let title: String
    let description: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(color.opacity(0.15))
                    .frame(width: 60, height: 60)
                
                Image(systemName: icon)
                    .font(.system(size: 28))
                    .foregroundColor(color)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.body)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color("BrandNavy"))
        .cornerRadius(16)
    }
}

// MARK: - Scan Tip Row

struct ScanTipRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundColor(.accentColor)
                .frame(width: 24)
            
            Text(text)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Spacer()
        }
    }
}

// MARK: - Patient Documents View

struct PatientDocumentsView: View {
    @EnvironmentObject var patientDataService: PatientDataService
    @EnvironmentObject var appState: AppState
    
    let patientId: String
    
    @State private var showingDocumentScanner = false
    @State private var selectedDocument: ScannedDocument?
    @State private var showingDocumentDetail = false
    
    var documents: [ScannedDocument] {
        patientDataService.documents(for: patientId)
    }
    
    var body: some View {
        List {
            Section {
                Button {
                    showingDocumentScanner = true
                } label: {
                    HStack {
                        Image(systemName: "doc.text.viewfinder")
                            .font(.title2)
                            .foregroundColor(.accentColor)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Scan New Document")
                                .font(.headline)
                                .foregroundColor(.primary)
                            Text("Add medical documents, EOBs, and more")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            
            if documents.isEmpty {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                        
                        Text("No Documents")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        Text("Scan documents to keep track of EOBs, statements, and other medical paperwork")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                }
            } else {
                // Group documents by type
                let groupedDocs = Dictionary(grouping: documents) { $0.documentType }
                
                ForEach(ScannedDocumentType.allCases, id: \.self) { docType in
                    if let docs = groupedDocs[docType], !docs.isEmpty {
                        Section(docType.rawValue) {
                            ForEach(docs) { doc in
                                DocumentRow(document: doc)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        selectedDocument = doc
                                        showingDocumentDetail = true
                                    }
                                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                        Button(role: .destructive) {
                                            patientDataService.deleteDocument(doc)
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Documents")
        .sheet(isPresented: $showingDocumentScanner) {
            DocumentClassifierScannerView()
        }
        .sheet(item: $selectedDocument) { doc in
            DocumentDetailView(document: doc)
        }
    }
}

// MARK: - Document Row

struct DocumentRow: View {
    let document: ScannedDocument
    
    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail or icon
            if let thumbnailData = document.thumbnailData,
               let thumbnail = UIImage(data: thumbnailData) {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 50, height: 50)
                    .cornerRadius(6)
                    .clipped()
            } else {
                Image(systemName: document.documentType.icon)
                    .font(.title2)
                    .foregroundColor(.accentColor)
                    .frame(width: 50, height: 50)
                    .background(Color.accentColor.opacity(0.1))
                    .cornerRadius(6)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(document.name)
                    .font(.headline)
                    .lineLimit(1)
                
                HStack {
                    Text(document.documentType.rawValue)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("•")
                        .foregroundColor(.secondary)
                    
                    Text(document.scannedAt, style: .date)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Document Detail View

struct DocumentDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var patientDataService: PatientDataService
    
    let document: ScannedDocument
    
    @State private var editedName: String = ""
    @State private var editedType: ScannedDocumentType = .other
    @State private var editedNotes: String = ""
    @State private var isEditing = false
    @State private var fullImage: UIImage?
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Full image
                    if let image = fullImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .cornerRadius(12)
                            .shadow(radius: 4)
                    } else if let thumbnailData = document.thumbnailData,
                              let thumbnail = UIImage(data: thumbnailData) {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .scaledToFit()
                            .cornerRadius(12)
                            .shadow(radius: 4)
                    } else {
                        Image(systemName: document.documentType.icon)
                            .font(.system(size: 80))
                            .foregroundColor(.accentColor)
                            .padding(40)
                            .background(Color.accentColor.opacity(0.1))
                            .cornerRadius(12)
                    }
                    
                    // Document info
                    VStack(alignment: .leading, spacing: 16) {
                        if isEditing {
                            TextField("Document Name", text: $editedName)
                                .textFieldStyle(.roundedBorder)
                            
                            Picker("Type", selection: $editedType) {
                                ForEach(ScannedDocumentType.allCases, id: \.self) { type in
                                    Label(type.rawValue, systemImage: type.icon)
                                        .tag(type)
                                }
                            }
                            
                            TextField("Notes", text: $editedNotes, axis: .vertical)
                                .textFieldStyle(.roundedBorder)
                                .lineLimit(3...6)
                        } else {
                            Text(document.name)
                                .font(.title2)
                                .fontWeight(.semibold)
                            
                            HStack {
                                Label(document.documentType.rawValue, systemImage: document.documentType.icon)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            
                            if let notes = document.notes, !notes.isEmpty {
                                Text(notes)
                                    .font(.body)
                                    .foregroundColor(.secondary)
                            }
                            
                            Divider()
                            
                            VStack(alignment: .leading, spacing: 8) {
                                InfoRow(label: "Scanned", value: document.scannedAt.formatted(date: .abbreviated, time: .shortened))
                                InfoRow(label: "File Size", value: document.fileSizeFormatted)
                                if document.pageCount > 1 {
                                    InfoRow(label: "Pages", value: "\(document.pageCount)")
                                }
                            }
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemGroupedBackground))
                    .cornerRadius(12)
                    
                    // Extracted text preview
                    if let fullText = document.fullText, !fullText.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Extracted Text")
                                .font(.headline)
                            
                            Text(fullText)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(10)
                        }
                        .padding()
                        .background(Color(.secondarySystemGroupedBackground))
                        .cornerRadius(12)
                    }
                }
                .padding()
            }
            .navigationTitle("Document")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .primaryAction) {
                    if isEditing {
                        Button("Save") {
                            saveEdits()
                        }
                    } else {
                        Button("Edit") {
                            startEditing()
                        }
                    }
                }
            }
            .onAppear {
                loadFullImage()
            }
        }
    }
    
    private func loadFullImage() {
        if let url = document.localFileURL,
           let data = try? Data(contentsOf: url),
           let image = UIImage(data: data) {
            fullImage = image
        }
    }
    
    private func startEditing() {
        editedName = document.name
        editedType = document.documentType
        editedNotes = document.notes ?? ""
        isEditing = true
    }
    
    private func saveEdits() {
        var updatedDoc = document
        updatedDoc.name = editedName
        updatedDoc.documentType = editedType
        updatedDoc.notes = editedNotes.isEmpty ? nil : editedNotes
        
        patientDataService.saveDocument(updatedDoc)
        isEditing = false
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
        }
    }
}

#Preview {
    MainTabView()
        .environmentObject(AppState())
        .environmentObject(PatientDataService.shared)
        .environmentObject(UserManager.shared)
}
