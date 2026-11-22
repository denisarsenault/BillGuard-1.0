//
//  SettingsView.swift
//  BillGuard (macOS)
//
//  Profile, sync, preferences and about — Mac port of the iOS Settings/Profile.
//

import SwiftUI
import SafariServices
import BillGuardCore

struct SettingsView: View {
    @StateObject private var userManager = UserManager.shared
    @StateObject private var data = PatientDataService.shared
    /// Whether the Safari extension is switched on in Safari; nil until known.
    @State private var safariExtensionEnabled: Bool?
    @State private var safariExtensionProblem: String?

    /// The Safari Web Extension embedded in this app (BillGuardWebExtensionMac).
    private static let safariExtensionID = "com.mybrightzone.BillGuardMac.WebExtension"

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    var body: some View {
        VStack(spacing: 0) {
            BrandHeader(title: "Settings", subtitle: "BillGuard MD")
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    profileCard
                    syncCard
                    safariCard
                    if let user = userManager.currentUser { preferencesCard(user) }
                    aboutCard
                }
                .padding(16)
                .frame(maxWidth: 640, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
        .brandScreen()
        .navigationTitle("Settings")
    }

    private var profileCard: some View {
        let user = userManager.currentUser
        let initials = user.map { "\($0.firstName.first.map(String.init) ?? "")\($0.lastName.first.map(String.init) ?? "")" }
        return HStack(spacing: 14) {
            ZStack {
                Circle().fill(Color.brandAccentGradient).frame(width: 56, height: 56)
                Text(initials?.isEmpty == false ? initials! : "BG")
                    .font(.title3.bold()).foregroundStyle(.black)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(user?.displayName ?? "Local Device").font(.title3.bold())
                if let user { Text(user.email).font(.callout).foregroundStyle(.secondary) }
                else { Text("Not signed in — data is stored on this Mac").font(.callout).foregroundStyle(.secondary) }
            }
            Spacer()
            if userManager.currentUser != nil {
                Button(role: .destructive) { userManager.logout() } label: {
                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                }.buttonStyle(.bordered)
            }
        }
        .navyCard()
    }

    private var syncCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("iCloud Sync", systemImage: "icloud").font(.headline).foregroundStyle(.brandCyan)
            settingRow("Container", "iCloud.com.billguard.BillGuard")
            settingRow("Patients", "\(data.patients.count)")
            settingRow("Bills", "\(data.claims.count)")
            Text("Patients and bills sync across your devices through iCloud/CloudKit.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .navyCard()
    }

    private var safariCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Safari Extension", systemImage: "safari").font(.headline).foregroundStyle(.brandCyan)
            settingRow("Status", safariExtensionEnabled.map { $0 ? "On" : "Off" } ?? "Unknown")
            Text("Adds a BillGuard button to Safari's toolbar. It reads the bill open in the tab, flags repeated and conflicting codes, and saves the bill to Web Captures.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let safariExtensionProblem {
                Text(safariExtensionProblem).font(.caption).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button("Open Safari Extension Settings…") {
                SFSafariApplication.showPreferencesForExtension(withIdentifier: Self.safariExtensionID) { error in
                    let message = error.map { "Safari could not be opened: \($0.localizedDescription)" }
                    DispatchQueue.main.async { safariExtensionProblem = message }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .navyCard()
        .task { await refreshSafariExtensionState() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await refreshSafariExtensionState() }
        }
    }

    private func refreshSafariExtensionState() async {
        let enabled: Bool? = await withCheckedContinuation { continuation in
            SFSafariExtensionManager.getStateOfSafariExtension(withIdentifier: Self.safariExtensionID) { state, _ in
                continuation.resume(returning: state?.isEnabled)
            }
        }
        safariExtensionEnabled = enabled
    }

    private func preferencesCard(_ user: User) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Preferences", systemImage: "slider.horizontal.3").font(.headline).foregroundStyle(.brandCyan)
            settingRow("Notifications", user.preferences.enableNotifications ? "On" : "Off")
            settingRow("Price Estimates", user.preferences.showPriceEstimates ? "Shown" : "Hidden")
            settingRow("Currency", user.preferences.defaultCurrency)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .navyCard()
    }

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("About", systemImage: "info.circle").font(.headline).foregroundStyle(.brandCyan)
            settingRow("Version", appVersion)
            settingRow("Codes in Database", "\(MedicalCodeDatabase.count)")
            Text("BillGuard helps you understand and organize medical bills. It is not medical or financial advice.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .navyCard()
    }

    private func settingRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).foregroundStyle(.primary)
        }
        .font(.callout)
    }
}
