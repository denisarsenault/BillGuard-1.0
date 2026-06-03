//
//  BillGuardApp.swift
//  BillGuard
//
//  Medical billing code lookup app
//

import SwiftUI

@main
struct BillGuardApp: App {
    @StateObject private var appState: AppState
    
    // Process start time — set at static init, before anything else
    static let processStart = CFAbsoluteTimeGetCurrent()
    
    init() {
        let t0 = CFAbsoluteTimeGetCurrent()
        print("⏱️ [LAUNCH] Time from process start to init(): \(Int((t0 - Self.processStart)*1000))ms")
        
        let state = AppState()
        _appState = StateObject(wrappedValue: state)
        print("⏱️ [LAUNCH] init() total: \(Int((CFAbsoluteTimeGetCurrent()-t0)*1000))ms")
    }
    
    var body: some Scene {
        let bodyStart = CFAbsoluteTimeGetCurrent()
        print("⏱️ [LAUNCH] Time from init() end to body: \(Int((bodyStart - Self.processStart)*1000))ms total from process start")
        
        return WindowGroup {
            RootView()
                .environmentObject(appState)
                .environmentObject(UserManager.shared)
                .environmentObject(PatientDataService.shared)
                .preferredColorScheme(.dark)
                .tint(Color("BrandCyan"))
                .onAppear {
                    print("⏱️ [LAUNCH] WindowGroup.onAppear: \(Int((CFAbsoluteTimeGetCurrent() - Self.processStart)*1000))ms from process start")
                }
        }
    }
}

// MARK: - Root View (Navigation Controller)

struct RootView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var userManager: UserManager
    @EnvironmentObject var patientDataService: PatientDataService
    
    @State private var showSplash = true
    @State private var isInitialized = false
    
    var body: some View {
        ZStack {
            Color("BrandDeepNavy")
                .ignoresSafeArea()
            
            if isInitialized {
                Group {
                    if !appState.hasCompletedOnboarding {
                        OnboardingView(hasCompletedOnboarding: $appState.hasCompletedOnboarding)
                    } else if !appState.isLoggedIn {
                        LoginView()
                    } else {
                        MainTabView()
                    }
                }
                .transition(.opacity)
                .animation(.easeInOut, value: appState.hasCompletedOnboarding)
                .animation(.easeInOut, value: appState.isLoggedIn)
                .animation(.easeInOut, value: isInitialized)
            }
            
            if showSplash {
                SplashScreenView {
                    print("⏱️ [Splash] onComplete: \(Int((CFAbsoluteTimeGetCurrent() - BillGuardApp.processStart)*1000))ms from process start")
                    withAnimation(.easeOut(duration: 0.5)) {
                        showSplash = false
                    }
                }
                .transition(.opacity)
                .zIndex(1)
            }
        }
        .onAppear {
            print("⏱️ [RootView] .onAppear: \(Int((CFAbsoluteTimeGetCurrent() - BillGuardApp.processStart)*1000))ms from process start")
            
            userManager.checkAuthState()
            if userManager.isAuthenticated {
                appState.isLoggedIn = true
            }
            isInitialized = true
            
            print("⏱️ [RootView] isInitialized=true: \(Int((CFAbsoluteTimeGetCurrent() - BillGuardApp.processStart)*1000))ms from process start")
            print("⏱️ [RootView] Showing: \(!appState.hasCompletedOnboarding ? "Onboarding" : !appState.isLoggedIn ? "Login" : "MainTabView")")
            
            // Apply UIKit appearance after first frame
            DispatchQueue.main.async {
                let navAppearance = UINavigationBarAppearance()
                navAppearance.configureWithOpaqueBackground()
                navAppearance.backgroundColor = UIColor(red: 0.051, green: 0.078, blue: 0.149, alpha: 1)
                navAppearance.titleTextAttributes = [.foregroundColor: UIColor.white]
                navAppearance.largeTitleTextAttributes = [.foregroundColor: UIColor.white]
                UINavigationBar.appearance().standardAppearance = navAppearance
                UINavigationBar.appearance().compactAppearance = navAppearance
                UINavigationBar.appearance().scrollEdgeAppearance = navAppearance
                UINavigationBar.appearance().tintColor = UIColor(red: 0, green: 0.824, blue: 0.902, alpha: 1)
                print("⏱️ [RootView] UIKit appearance done: \(Int((CFAbsoluteTimeGetCurrent() - BillGuardApp.processStart)*1000))ms from process start")
            }
        }
        .onChange(of: userManager.isAuthenticated) { _, isAuthenticated in
            appState.isLoggedIn = isAuthenticated
        }
    }
}

// MARK: - App State

@MainActor
class AppState: ObservableObject {
    @Published var hasCompletedOnboarding: Bool
    @Published var isLoggedIn: Bool
    @Published var searchViewModel: SearchViewModel
    @Published var favoritesManager: FavoritesManager
    
    /// Currently selected patient ID
    @Published var selectedPatientId: String?
    
    /// Currently selected tab index (0=Search, 1=Bills, 2=Patients, etc.)
    @Published var selectedTab: Int = 0
    
    /// ID of the most recently saved claim — used for "NEW" badge and auto-scroll
    @Published var lastSavedClaimId: String?
    
    /// Timestamp of last save — badge expires after 5 minutes
    @Published var lastSavedClaimDate: Date?
    
    let cloudKitService: CloudKitService
    
    init() {
        let t0 = CFAbsoluteTimeGetCurrent()
        
        self.hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        self.isLoggedIn = UserDefaults.standard.bool(forKey: "isLoggedIn")
        self.selectedPatientId = UserDefaults.standard.string(forKey: "selectedPatientId")
        
        let t1 = CFAbsoluteTimeGetCurrent()
        print("⏱️ [AppState] UserDefaults reads: \(Int((t1-t0)*1000))ms")
        
        let cloudKit = CloudKitService()
        let t2 = CFAbsoluteTimeGetCurrent()
        print("⏱️ [AppState] CloudKitService(): \(Int((t2-t1)*1000))ms")
        
        self.cloudKitService = cloudKit
        self.searchViewModel = SearchViewModel(cloudKitService: cloudKit)
        let t3 = CFAbsoluteTimeGetCurrent()
        print("⏱️ [AppState] SearchViewModel(): \(Int((t3-t2)*1000))ms")
        
        self.favoritesManager = FavoritesManager()
        let t4 = CFAbsoluteTimeGetCurrent()
        print("⏱️ [AppState] FavoritesManager(): \(Int((t4-t3)*1000))ms")
        print("⏱️ [AppState] Total: \(Int((t4-t0)*1000))ms")
    }
    
    func completeOnboarding() {
        hasCompletedOnboarding = true
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
    }
    
    /// Navigate to Bills tab and highlight a specific claim
    func navigateToSavedBill(claimId: String) {
        lastSavedClaimId = claimId
        lastSavedClaimDate = Date()
        selectedTab = 1  // Bills tab
    }
    
    /// Check if a claim should show the "NEW" badge
    func isNewlySaved(claimId: String) -> Bool {
        guard claimId == lastSavedClaimId,
              let date = lastSavedClaimDate else { return false }
        // Badge expires after 5 minutes
        return Date().timeIntervalSince(date) < 300
    }
    
    /// Clear the "NEW" badge for a specific claim (user has viewed it)
    func clearNewBadge(for claimId: String) {
        if claimId == lastSavedClaimId {
            lastSavedClaimId = nil
            lastSavedClaimDate = nil
        }
    }
    
    func logout() {
        isLoggedIn = false
        selectedPatientId = nil
        lastSavedClaimId = nil
        lastSavedClaimDate = nil
        UserDefaults.standard.set(false, forKey: "isLoggedIn")
        UserDefaults.standard.removeObject(forKey: "selectedPatientId")
        UserManager.shared.logout()
        PatientDataService.shared.clearCache()
    }
    
    func selectPatient(_ patientId: String?) {
        selectedPatientId = patientId
        if let id = patientId {
            UserDefaults.standard.set(id, forKey: "selectedPatientId")
        } else {
            UserDefaults.standard.removeObject(forKey: "selectedPatientId")
        }
    }
}
