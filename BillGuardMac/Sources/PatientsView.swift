//
//  PatientsView.swift
//  BillGuard (macOS)
//
//
//  Medical billing code lookup app

//  Lists patients from the shared BillGuardCore data layer (local cache today,
//  CloudKit-synced once the container/entitlement are configured).
//

import SwiftUI
import BillGuardCore

struct PatientsView: View {
    @StateObject private var data = PatientDataService.shared
    @State private var selection: Patient.ID?

    var body: some View {
        NavigationStack {
            Group {
                if data.patients.isEmpty {
                    emptyState
                } else {
                    List(data.patients, selection: $selection) { patient in
                        NavigationLink(value: patient.id) {
                            PatientRow(patient: patient,
                                       billCount: data.claims(for: patient.id).count)
                        }
                        .tag(patient.id)
                    }
                }
            }
            .navigationTitle("Patients")
            .navigationDestination(for: Patient.ID.self) { id in
                if let patient = data.patients.first(where: { $0.id == id }) {
                    PatientDetailView(patient: patient)
                }
            }
            .overlay(alignment: .bottom) {
                if data.isLoading {
                    ProgressView().padding(8)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "person.2.badge.gearshape")
                .font(.system(size: 44))
                .foregroundStyle(.tint)
            Text("No Patients Yet").font(.title2.bold())
            Text("Patients and their bills sync here from CloudKit, or are created when you scan a document or capture a bill from a web portal.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

private struct PatientRow: View {
    let patient: Patient
    let billCount: Int

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(.tint.opacity(0.15)).frame(width: 36, height: 36)
                Text(patient.initials).font(.caption.bold()).foregroundStyle(.tint)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(patient.displayName).font(.body.weight(.medium))
                HStack(spacing: 6) {
                    if let age = patient.age { Text("Age \(age)") }
                    if patient.age != nil && billCount > 0 { Text("·") }
                    if billCount > 0 { Text("\(billCount) bill\(billCount == 1 ? "" : "s")") }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}
