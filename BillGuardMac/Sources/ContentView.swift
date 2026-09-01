//
//  ContentView.swift
//  BillGuard (macOS)
//
//  App shell: a sidebar-driven layout mirroring the iOS app's sections. Each
//  section is a placeholder for now; they get wired to BillGuardCore
//  (CloudKit-backed patients/claims), the file-import document scanner, and the
//  code search in subsequent steps.
//

import SwiftUI
import BillGuardCore

struct ContentView: View {
    enum Section: String, CaseIterable, Identifiable {
        case patients   = "Patients"
        case scan       = "Scan Document"
        case search     = "Search & Codes"
        case captures   = "Web Captures"
        case settings   = "Settings"
        var id: String { rawValue }

        var systemImage: String {
            switch self {
            case .patients: return "person.2.fill"
            case .scan:     return "doc.viewfinder"
            case .search:   return "magnifyingglass"
            case .captures: return "globe"
            case .settings: return "gearshape"
            }
        }
    }

    @State private var selection: Section? = .patients

    var body: some View {
        NavigationSplitView {
            List(Section.allCases, selection: $selection) { section in
                Label(section.rawValue, systemImage: section.systemImage)
                    .tag(section)
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
            .navigationTitle("BillGuard")
        } detail: {
            switch selection ?? .patients {
            case .patients: PatientsView()
            case .scan: PlaceholderView(
                title: "Scan a Document",
                systemImage: "doc.viewfinder",
                message: "Import a photo or PDF of a medical bill (⌘O) — it's processed with the same on-device text recognition and parsing as the iOS app. No camera on Mac.")
            case .search: PlaceholderView(
                title: "Search & Codes",
                systemImage: "magnifyingglass",
                message: "Look up CPT/HCPCS/ICD codes and typical prices.")
            case .captures: PlaceholderView(
                title: "Web Captures",
                systemImage: "globe",
                message: "Bills captured from patient/insurance portals by the BillGuard browser extension appear here for review.")
            case .settings: PlaceholderView(
                title: "Settings",
                systemImage: "gearshape",
                message: "iCloud account, CloudKit sync status, and preferences.")
            }
        }
    }
}

private struct PlaceholderView: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text(title).font(.largeTitle.bold())
            Text(message)
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

#Preview {
    ContentView()
}
