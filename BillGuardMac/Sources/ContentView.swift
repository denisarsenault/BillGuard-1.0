//
//  ContentView.swift
//  BillGuard (macOS)
//
//  App shell: a branded sidebar mirroring the iOS app's tabs (Search & Add,
//  Bills, Patients, Providers, Saved, Insurance, Visits, Payments, Settings),
//  plus a Mac-only "Scan Document" (file import) that stands in for the iOS
//  camera, and "Web Captures" for the browser extension.
//

import SwiftUI
import BillGuardCore

struct ContentView: View {
    enum Section: String, CaseIterable, Identifiable {
        case search     = "Search & Add"
        case bills      = "Bills"
        case patients   = "Patients"
        case providers  = "Providers"
        case saved      = "Saved"
        case insurance  = "Insurance"
        case visits     = "Visits"
        case payments   = "Payments"
        case scan       = "Scan Document"
        case captures   = "Web Captures"
        case settings   = "Settings"
        var id: String { rawValue }

        var systemImage: String {
            switch self {
            case .search:    return "magnifyingglass"
            case .bills:     return "doc.text.fill"
            case .patients:  return "person.2.fill"
            case .providers: return "building.2.fill"
            case .saved:     return "star.fill"
            case .insurance: return "shield.lefthalf.filled"
            case .visits:    return "calendar.badge.clock"
            case .payments:  return "creditcard.fill"
            case .scan:      return "doc.viewfinder"
            case .captures:  return "globe"
            case .settings:  return "gearshape.fill"
            }
        }
    }

    struct NavGroup: Identifiable {
        let id = UUID()
        let title: String
        let items: [Section]
    }

    // Sidebar grouping, mirroring the iOS tab order.
    static let groups: [NavGroup] = [
        NavGroup(title: "Records", items: [.search, .bills, .patients, .providers, .saved]),
        NavGroup(title: "Billing", items: [.insurance, .visits, .payments]),
        NavGroup(title: "Capture", items: [.scan, .captures]),
        NavGroup(title: "",        items: [.settings]),
    ]

    @State private var selection: Section? = .search
    @StateObject private var favorites = FavoritesManager.shared

    var body: some View {
        VStack(spacing: 0) {
            WindowBrandBar()
            NavigationSplitView {
                List(selection: $selection) {
                    ForEach(Self.groups) { group in
                        SidebarGroup(group: group, favoritesCount: favorites.count)
                    }
                }
                .navigationSplitViewColumnWidth(min: 210, ideal: 230)
            } detail: {
                detail(for: selection ?? .search)
            }
        }
        .ignoresSafeArea(.container, edges: .top)
    }

    @ViewBuilder
    private func detail(for section: Section) -> some View {
        switch section {
        case .search:    SearchAddView()
        case .bills:     BillsView()
        case .patients:  PatientsView()
        case .providers: ProvidersView()
        case .saved:     SavedView()
        case .insurance: InsuranceView()
        case .visits:    VisitsView()
        case .payments:  PaymentsView()
        case .scan:      ScanDocumentView()
        case .captures:  PlaceholderView(
            title: "Web Captures", systemImage: "globe",
            message: "Bills captured from patient/insurance portals by the BillGuard browser extension appear here for review.")
        case .settings:  SettingsView()
        }
    }
}

private struct SidebarGroup: View {
    let group: ContentView.NavGroup
    let favoritesCount: Int

    var body: some View {
        SwiftUI.Section(header: header) {
            ForEach(group.items) { section in
                SidebarRow(section: section,
                           badge: section == .saved ? favoritesCount : 0)
                    .tag(section)
            }
        }
    }

    @ViewBuilder private var header: some View {
        if !group.title.isEmpty { Text(group.title) }
    }
}

private struct SidebarRow: View {
    let section: ContentView.Section
    let badge: Int

    var body: some View {
        Label {
            HStack {
                Text(section.rawValue)
                if badge > 0 {
                    Spacer()
                    Text("\(badge)")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Color.brandCyan, in: Capsule())
                }
            }
        } icon: {
            Image(systemName: section.systemImage)
                .foregroundStyle(Color.brandCyan)
        }
    }
}

struct PlaceholderView: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.system(size: 48))
                .foregroundStyle(Color.brandCyan)
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
