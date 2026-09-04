//
//  SettingsView.swift
//  BillGuard (macOS)
//
//  Profile, sync, preferences and about — Mac port of the iOS Settings/Profile.
//

import SwiftUI
import BillGuardCore

struct SettingsView: View {
    @StateObject private var userManager = UserManager.shared
    @StateObject private var data = PatientDataService.shared

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
