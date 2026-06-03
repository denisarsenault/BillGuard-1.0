//
//  ProviderViews.swift
//  BillGuard
//
//  Provider management views including map, list, and detail views
//

import SwiftUI
import MapKit
import CoreLocation

// MARK: - Provider List View

struct ProviderListView: View {
    var body: some View {
        NavigationStack {
            ProviderListViewContent()
        }
    }
}

struct ProviderListViewContent: View {
    @EnvironmentObject var patientDataService: PatientDataService
    
    @State private var showingAddProvider = false
    @State private var showingMap = false
    @State private var searchText = ""
    
    var filteredProviders: [Provider] {
        if searchText.isEmpty {
            return patientDataService.providers
        }
        return patientDataService.providers.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.providerType.rawValue.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        Group {
            if patientDataService.providers.isEmpty {
                emptyStateView
            } else {
                providerListContent
            }
        }
        .navigationTitle("Providers").brandToolbar(title: "Providers", showPatient: true)
        .searchable(text: $searchText, prompt: "Search providers")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        showingAddProvider = true
                    } label: {
                        Label("Add Provider", systemImage: "plus")
                    }
                    
                    Button {
                        showingMap = true
                    } label: {
                        Label("View Map", systemImage: "map")
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddProvider) {
            AddProviderView()
                .environmentObject(patientDataService)
        }
        .sheet(isPresented: $showingMap) {
            ProviderMapView(providers: patientDataService.providers)
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "building.2")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text("No Providers")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Add healthcare providers to enable location-based reminders and track your visits.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Button {
                showingAddProvider = true
            } label: {
                Label("Add Provider", systemImage: "plus")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.accentColor)
                    .cornerRadius(10)
            }
        }
    }
    
    private var providerListContent: some View {
        List {
            // Map preview
            Section {
                Button {
                    showingMap = true
                } label: {
                    HStack {
                        Image(systemName: "map.fill")
                            .foregroundColor(.accentColor)
                        Text("View All on Map")
                        Spacer()
                        Text("\(patientDataService.providers.filter { $0.hasLocation }.count) locations")
                            .foregroundColor(.secondary)
                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                }
                .foregroundColor(.primary)
            }
            
            // Providers by type
            ForEach(ProviderType.allCases, id: \.self) { type in
                let providersOfType = filteredProviders.filter { $0.providerType == type }
                if !providersOfType.isEmpty {
                    Section(header: providerTypeHeader(type, count: providersOfType.count)) {
                        ForEach(providersOfType) { provider in
                            NavigationLink {
                                ProviderDetailView(provider: provider)
                                    .environmentObject(patientDataService)
                            } label: {
                                ProviderRow(provider: provider)
                            }
                        }
                        .onDelete { offsets in
                            deleteProviders(at: offsets, from: providersOfType)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }
    
    private func providerTypeHeader(_ type: ProviderType, count: Int) -> some View {
        HStack {
            Image(systemName: type.icon)
            Text(type.rawValue)
            Spacer()
            Text("\(count)")
                .foregroundColor(.secondary)
        }
    }
    
    private func deleteProviders(at offsets: IndexSet, from providers: [Provider]) {
        for index in offsets {
            let provider = providers[index]
            patientDataService.deleteProvider(provider)
            LocationReminderService.shared.stopMonitoringProvider(provider)
        }
    }
}

// MARK: - Provider Row

struct ProviderRow: View {
    let provider: Provider
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 44, height: 44)
                
                Image(systemName: provider.providerType.icon)
                    .foregroundColor(.accentColor)
            }
            
            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(provider.name)
                    .font(.headline)
                
                if let specialty = provider.specialty {
                    Text(specialty.rawValue)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if let address = provider.address {
                    Text(address.cityStateZip)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Status indicators
            VStack(alignment: .trailing, spacing: 4) {
                if provider.hasLocation {
                    if provider.isGeofenceActive {
                        Image(systemName: "location.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                    } else {
                        Image(systemName: "location.slash")
                            .foregroundColor(.orange)
                            .font(.caption)
                    }
                }
                
                if provider.visitCount > 0 {
                    Text("\(provider.visitCount) visits")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Location Permission Banner

struct LocationPermissionBanner: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "location.fill")
                    .foregroundColor(.orange)
                Text("Enable Location Reminders")
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            
            Text("Allow \"Always\" location access to receive reminders when you visit healthcare providers.")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Button("Enable Location") {
                LocationReminderService.shared.requestAlwaysAuthorization()
            }
            .font(.caption)
            .buttonStyle(.borderedProminent)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Provider Map View

struct ProviderMapView: View {
    let providers: [Provider]
    
    @Environment(\.dismiss) private var dismiss
    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
            span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
        )
    )
    @State private var selectedProvider: Provider?
    
    var providersWithLocation: [Provider] {
        providers.filter { $0.hasLocation }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Map(position: $cameraPosition) {
                    ForEach(providersWithLocation) { provider in
                        Annotation("", coordinate: provider.coordinate!) {
                            ProviderMapPin(provider: provider, isSelected: selectedProvider?.id == provider.id)
                                .onTapGesture {
                                    withAnimation {
                                        selectedProvider = provider
                                    }
                                }
                        }
                    }
                }
                .ignoresSafeArea(edges: .bottom)
                
                // Selected provider card
                if let provider = selectedProvider {
                    VStack {
                        Spacer()
                        ProviderMapCard(provider: provider) {
                            selectedProvider = nil
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Provider Locations")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        fitAllAnnotations()
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                    }
                }
            }
            .onAppear {
                fitAllAnnotations()
            }
        }
    }
    
    private func fitAllAnnotations() {
        guard !providersWithLocation.isEmpty else { return }
        
        let coordinates = providersWithLocation.compactMap { $0.coordinate }
        
        var minLat = coordinates[0].latitude
        var maxLat = coordinates[0].latitude
        var minLon = coordinates[0].longitude
        var maxLon = coordinates[0].longitude
        
        for coord in coordinates {
            minLat = min(minLat, coord.latitude)
            maxLat = max(maxLat, coord.latitude)
            minLon = min(minLon, coord.longitude)
            maxLon = max(maxLon, coord.longitude)
        }
        
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        
        let span = MKCoordinateSpan(
            latitudeDelta: (maxLat - minLat) * 1.5 + 0.01,
            longitudeDelta: (maxLon - minLon) * 1.5 + 0.01
        )
        
        withAnimation {
            cameraPosition = .region(MKCoordinateRegion(center: center, span: span))
        }
    }
}

// MARK: - Provider Map Pin

struct ProviderMapPin: View {
    let provider: Provider
    let isSelected: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(isSelected ? Color.accentColor : Color.white)
                    .frame(width: isSelected ? 44 : 36, height: isSelected ? 44 : 36)
                    .shadow(radius: 3)
                
                Image(systemName: provider.providerType.icon)
                    .font(isSelected ? .body : .caption)
                    .foregroundColor(isSelected ? .white : .accentColor)
            }
            
            // Triangle pointer
            Triangle()
                .fill(isSelected ? Color.accentColor : Color.white)
                .frame(width: 12, height: 8)
                .offset(y: -2)
        }
        .animation(.spring(response: 0.3), value: isSelected)
    }
}

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Provider Map Card

struct ProviderMapCard: View {
    let provider: Provider
    let onDismiss: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: provider.providerType.icon)
                    .foregroundColor(.accentColor)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(provider.name)
                        .font(.headline)
                    
                    if let specialty = provider.specialty {
                        Text(specialty.rawValue)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
            
            if let address = provider.address {
                Text(address.formatted)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            HStack(spacing: 12) {
                // Directions button
                if let coordinate = provider.coordinate {
                    Button {
                        openInMaps(coordinate: coordinate, name: provider.name)
                    } label: {
                        Label("Directions", systemImage: "arrow.triangle.turn.up.right.diamond")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                }
                
                // Call button
                if let phone = provider.primaryPhone {
                    Button {
                        callPhone(phone)
                    } label: {
                        Label("Call", systemImage: "phone")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                }
                
                Spacer()
                
                // Geofence status
                if provider.isGeofenceActive {
                    Label("Reminders On", systemImage: "bell.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .shadow(radius: 10)
        )
    }
    
    private func openInMaps(coordinate: CLLocationCoordinate2D, name: String) {
        let placemark = MKPlacemark(coordinate: coordinate)
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.name = name
        mapItem.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
    }
    
    private func callPhone(_ phone: String) {
        let digits = phone.filter { $0.isNumber }
        if let url = URL(string: "tel://\(digits)") {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Add Provider View

struct AddProviderView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var patientDataService: PatientDataService
    
    // Provider Info
    @State private var name = ""
    @State private var providerType: ProviderType = .doctor
    @State private var specialty: ProviderSpecialty = .generalPractice
    
    // Contact
    @State private var phone = ""
    @State private var fax = ""
    @State private var email = ""
    @State private var website = ""
    
    // Business / Identifiers
    @State private var npi = ""
    @State private var taxId = ""
    @State private var licenseNumber = ""
    
    // Address
    @State private var street1 = ""
    @State private var street2 = ""
    @State private var city = ""
    @State private var state = ""
    @State private var zipCode = ""
    
    // Billing Contact
    @State private var showBillingSection = false
    @State private var billingStreet1 = ""
    @State private var billingStreet2 = ""
    @State private var billingCity = ""
    @State private var billingState = ""
    @State private var billingZipCode = ""
    @State private var billingPhone = ""
    @State private var billingEmail = ""
    @State private var billingFax = ""
    
    // Reminder settings
    @State private var enableReminders = true
    @State private var geofenceRadius: Double = 100
    
    // Notes
    @State private var notes = ""
    
    @State private var isGeocoding = false
    @State private var geocodeError: String?
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
                            Image(systemName: "doc.text.viewfinder").font(.title3).frame(width: 30)
                            Text("Scan Provider Info").fontWeight(.semibold)
                            Spacer()
                            Image(systemName: "chevron.right").foregroundColor(.white)
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                }
                
                Section("Provider Information") {
                    TextField("Provider / Facility Name", text: $name)
                    
                    Picker("Type", selection: $providerType) {
                        ForEach(ProviderType.allCases, id: \.self) { type in
                            Label(type.rawValue, systemImage: type.icon)
                                .tag(type)
                        }
                    }
                    
                    Picker("Specialty", selection: $specialty) {
                        ForEach(ProviderSpecialty.allCases, id: \.self) { spec in
                            Text(spec.rawValue).tag(spec)
                        }
                    }
                }
                
                Section("Contact") {
                    TextField("Phone", text: $phone)
                        .keyboardType(.phonePad)
                    
                    TextField("Fax", text: $fax)
                        .keyboardType(.phonePad)
                    
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                    
                    TextField("Website", text: $website)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                }
                
                Section("Business Information") {
                    TextField("NPI (National Provider Identifier)", text: $npi)
                        .keyboardType(.numberPad)
                    
                    TextField("Tax ID / EIN", text: $taxId)
                        .keyboardType(.numberPad)
                    
                    TextField("License Number", text: $licenseNumber)
                }
                
                Section("Address") {
                    TextField("Street Address", text: $street1)
                    TextField("Suite / Unit", text: $street2)
                    TextField("City", text: $city)
                    
                    Picker("State", selection: $state) {
                        Text("Select State").tag("")
                        ForEach(USState.all, id: \.abbreviation) { usState in
                            Text(usState.name).tag(usState.abbreviation)
                        }
                    }
                    
                    TextField("ZIP Code", text: $zipCode)
                        .keyboardType(.numberPad)
                }
                
                Section {
                    DisclosureGroup("Billing Contact", isExpanded: $showBillingSection) {
                        Group {
                            TextField("Billing Street Address", text: $billingStreet1)
                            TextField("Suite / Unit", text: $billingStreet2)
                            TextField("City", text: $billingCity)
                            
                            Picker("State", selection: $billingState) {
                                Text("Select State").tag("")
                                ForEach(USState.all, id: \.abbreviation) { usState in
                                    Text(usState.name).tag(usState.abbreviation)
                                }
                            }
                            
                            TextField("ZIP Code", text: $billingZipCode)
                                .keyboardType(.numberPad)
                            
                            TextField("Billing Phone", text: $billingPhone)
                                .keyboardType(.phonePad)
                            
                            TextField("Billing Email", text: $billingEmail)
                                .keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never)
                            
                            TextField("Billing Fax", text: $billingFax)
                                .keyboardType(.phonePad)
                        }
                    }
                }
                
                Section("Location Reminders") {
                    Toggle("Enable Visit Reminders", isOn: $enableReminders)
                    
                    if enableReminders {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Reminder Radius: \(Int(geofenceRadius))m")
                                .font(.subheadline)
                            
                            Slider(value: $geofenceRadius, in: 50...500, step: 25)
                            
                            Text("You'll be reminded when entering this radius around the provider's location.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 80)
                }
                
                if let error = geocodeError {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Add Provider")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveProvider()
                    }
                    .disabled(name.isEmpty || isGeocoding)
                }
            }
            .delayedLoadingOverlay(isLoading: isGeocoding, delay: 2.0, message: "Finding location...", style: .ring)
            .sheet(isPresented: $showingScanner) {
                ContactInfoScannerView(mode: .provider) { info in
                    applyScannedInfo(info)
                }
            }
        }
    }
    
    private func applyScannedInfo(_ info: ExtractedContactInfo) {
        if name.isEmpty {
            if !info.organization.isEmpty { name = info.organization }
            else if !info.name.isEmpty { name = info.name }
        }
        if !info.phone.isEmpty && phone.isEmpty { phone = info.phone }
        if !info.fax.isEmpty && fax.isEmpty { fax = info.fax }
        if !info.email.isEmpty && email.isEmpty { email = info.email }
        if !info.website.isEmpty && website.isEmpty { website = info.website }
        if !info.npi.isEmpty && npi.isEmpty { npi = info.npi }
        if !info.address.isEmpty && street1.isEmpty { street1 = info.address }
        if !info.city.isEmpty && city.isEmpty { city = info.city }
        if !info.state.isEmpty && state.isEmpty { state = info.state }
        if !info.zipCode.isEmpty && zipCode.isEmpty { zipCode = info.zipCode }
        
        // Guess provider type
        let orgLower = (info.organization + " " + info.name).lowercased()
        if orgLower.contains("hospital") { providerType = .hospital }
        else if orgLower.contains("emergency") { providerType = .emergencyRoom }
        else if orgLower.contains("pharmacy") { providerType = .pharmacy }
        else if orgLower.contains("urgent") { providerType = .urgentCare }
        else if orgLower.contains("lab") { providerType = .laboratory }
        else if orgLower.contains("imaging") || orgLower.contains("radiology") { providerType = .imagingCenter }
        else if orgLower.contains("dental") || orgLower.contains("dentist") { providerType = .dentist }
        else if orgLower.contains("eye") || orgLower.contains("vision") || orgLower.contains("optical") { providerType = .optometrist }
        else if orgLower.contains("therap") || orgLower.contains("counsel") { providerType = .therapist }
        else if orgLower.contains("clinic") || orgLower.contains("medical center") { providerType = .clinic }
        else if orgLower.contains("dr.") || orgLower.contains("dr ") || orgLower.contains(" md") { providerType = .doctor }
    }
    
    private func saveProvider() {
        var address: Address?
        if !street1.isEmpty || !city.isEmpty || !state.isEmpty {
            address = Address(
                type: .work,
                street1: street1,
                street2: street2.isEmpty ? nil : street2,
                city: city,
                state: state,
                zipCode: zipCode,
                isPrimary: true
            )
        }
        
        var billingAddress: Address?
        if !billingStreet1.isEmpty || !billingCity.isEmpty || !billingState.isEmpty {
            billingAddress = Address(
                type: .billing,
                street1: billingStreet1,
                street2: billingStreet2.isEmpty ? nil : billingStreet2,
                city: billingCity,
                state: billingState,
                zipCode: billingZipCode
            )
        }
        
        var phones: [PhoneNumber] = []
        if !phone.isEmpty {
            phones.append(PhoneNumber(label: .main, number: phone, isPrimary: true))
        }
        
        var emails: [String] = []
        if !email.isEmpty { emails.append(email) }
        
        let reminderSettings = ProviderReminderSettings(
            isEnabled: enableReminders,
            geofenceRadius: geofenceRadius
        )
        
        let provider = Provider(
            name: name,
            providerType: providerType,
            specialty: specialty,
            address: address,
            phones: phones,
            emails: emails,
            fax: fax.isEmpty ? nil : fax,
            website: website.isEmpty ? nil : website,
            npi: npi.isEmpty ? nil : npi,
            taxId: taxId.isEmpty ? nil : taxId,
            licenseNumber: licenseNumber.isEmpty ? nil : licenseNumber,
            billingAddress: billingAddress,
            billingPhone: billingPhone.isEmpty ? nil : billingPhone,
            billingEmail: billingEmail.isEmpty ? nil : billingEmail,
            billingFax: billingFax.isEmpty ? nil : billingFax,
            reminderSettings: reminderSettings,
            isGeofenceActive: enableReminders,
            notes: notes.isEmpty ? nil : notes
        )
        
        // Geocode the address if provided
        if address != nil {
            isGeocoding = true
            
            Task { @MainActor in
                var providerToGeocode = provider
                let success = await LocationReminderService.shared.geocodeAndUpdateProvider(&providerToGeocode)
                
                isGeocoding = false
                
                if !success && enableReminders {
                    geocodeError = "Could not find location for address. Reminders may not work."
                }
                
                patientDataService.saveProvider(providerToGeocode)
                
                if success && enableReminders {
                    LocationReminderService.shared.startMonitoringProvider(providerToGeocode)
                }
                
                dismiss()
            }
        } else {
            patientDataService.saveProvider(provider)
            dismiss()
        }
    }
}

// MARK: - Edit Provider View

struct EditProviderView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var patientDataService: PatientDataService
    
    @Binding var provider: Provider
    var onSave: () -> Void
    
    // Provider Info
    @State private var name: String
    @State private var providerType: ProviderType
    @State private var specialty: ProviderSpecialty?
    
    // Contact
    @State private var phone: String
    @State private var fax: String
    @State private var email: String
    @State private var website: String
    
    // Business / Identifiers
    @State private var npi: String
    @State private var taxId: String
    @State private var licenseNumber: String
    
    // Address
    @State private var street1: String
    @State private var street2: String
    @State private var city: String
    @State private var state: String
    @State private var zipCode: String
    
    // Billing Contact
    @State private var showBillingSection: Bool
    @State private var billingStreet1: String
    @State private var billingStreet2: String
    @State private var billingCity: String
    @State private var billingState: String
    @State private var billingZipCode: String
    @State private var billingPhone: String
    @State private var billingEmail: String
    @State private var billingFax: String
    
    // Reminder settings
    @State private var enableReminders: Bool
    @State private var geofenceRadius: Double
    
    // Notes
    @State private var notes: String
    
    @State private var isGeocoding = false
    @State private var geocodeError: String?
    @State private var showingScanner = false
    
    init(provider: Binding<Provider>, onSave: @escaping () -> Void) {
        self._provider = provider
        self.onSave = onSave
        
        let p = provider.wrappedValue
        _name = State(initialValue: p.name)
        _providerType = State(initialValue: p.providerType)
        _specialty = State(initialValue: p.specialty)
        _phone = State(initialValue: p.primaryPhone ?? "")
        _fax = State(initialValue: p.fax ?? "")
        _email = State(initialValue: p.primaryEmail ?? "")
        _website = State(initialValue: p.website ?? "")
        _npi = State(initialValue: p.npi ?? "")
        _taxId = State(initialValue: p.taxId ?? "")
        _licenseNumber = State(initialValue: p.licenseNumber ?? "")
        _notes = State(initialValue: p.notes ?? "")
        
        _street1 = State(initialValue: p.address?.street1 ?? "")
        _street2 = State(initialValue: p.address?.street2 ?? "")
        _city = State(initialValue: p.address?.city ?? "")
        _state = State(initialValue: p.address?.state ?? "")
        _zipCode = State(initialValue: p.address?.zipCode ?? "")
        
        let hasBilling = p.billingAddress != nil || p.billingPhone != nil || p.billingEmail != nil || p.billingFax != nil
        _showBillingSection = State(initialValue: hasBilling)
        _billingStreet1 = State(initialValue: p.billingAddress?.street1 ?? "")
        _billingStreet2 = State(initialValue: p.billingAddress?.street2 ?? "")
        _billingCity = State(initialValue: p.billingAddress?.city ?? "")
        _billingState = State(initialValue: p.billingAddress?.state ?? "")
        _billingZipCode = State(initialValue: p.billingAddress?.zipCode ?? "")
        _billingPhone = State(initialValue: p.billingPhone ?? "")
        _billingEmail = State(initialValue: p.billingEmail ?? "")
        _billingFax = State(initialValue: p.billingFax ?? "")
        
        _enableReminders = State(initialValue: p.reminderSettings.isEnabled)
        _geofenceRadius = State(initialValue: p.reminderSettings.geofenceRadius)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                // Scan Button
                Section {
                    Button {
                        showingScanner = true
                    } label: {
                        HStack {
                            Image(systemName: "doc.text.viewfinder").font(.title3).frame(width: 30)
                            Text("Scan to Update").fontWeight(.semibold)
                            Spacer()
                            Image(systemName: "chevron.right").foregroundColor(.white)
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                }
                
                Section("Provider Information") {
                    TextField("Provider / Facility Name", text: $name)
                    
                    Picker("Type", selection: $providerType) {
                        ForEach(ProviderType.allCases, id: \.self) { type in
                            Label(type.rawValue, systemImage: type.icon)
                                .tag(type)
                        }
                    }
                    
                    Picker("Specialty", selection: $specialty) {
                        Text("None").tag(nil as ProviderSpecialty?)
                        ForEach(ProviderSpecialty.allCases, id: \.self) { spec in
                            Text(spec.rawValue).tag(spec as ProviderSpecialty?)
                        }
                    }
                }
                
                Section("Contact") {
                    TextField("Phone", text: $phone)
                        .keyboardType(.phonePad)
                    
                    TextField("Fax", text: $fax)
                        .keyboardType(.phonePad)
                    
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                    
                    TextField("Website", text: $website)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                }
                
                Section("Business Information") {
                    TextField("NPI (National Provider Identifier)", text: $npi)
                        .keyboardType(.numberPad)
                    
                    TextField("Tax ID / EIN", text: $taxId)
                        .keyboardType(.numberPad)
                    
                    TextField("License Number", text: $licenseNumber)
                }
                
                Section("Address") {
                    TextField("Street Address", text: $street1)
                    TextField("Suite / Unit", text: $street2)
                    TextField("City", text: $city)
                    
                    Picker("State", selection: $state) {
                        Text("Select State").tag("")
                        ForEach(USState.all, id: \.abbreviation) { usState in
                            Text(usState.name).tag(usState.abbreviation)
                        }
                    }
                    
                    TextField("ZIP Code", text: $zipCode)
                        .keyboardType(.numberPad)
                }
                
                Section {
                    DisclosureGroup("Billing Contact", isExpanded: $showBillingSection) {
                        Group {
                            TextField("Billing Street Address", text: $billingStreet1)
                            TextField("Suite / Unit", text: $billingStreet2)
                            TextField("City", text: $billingCity)
                            
                            Picker("State", selection: $billingState) {
                                Text("Select State").tag("")
                                ForEach(USState.all, id: \.abbreviation) { usState in
                                    Text(usState.name).tag(usState.abbreviation)
                                }
                            }
                            
                            TextField("ZIP Code", text: $billingZipCode)
                                .keyboardType(.numberPad)
                            
                            TextField("Billing Phone", text: $billingPhone)
                                .keyboardType(.phonePad)
                            
                            TextField("Billing Email", text: $billingEmail)
                                .keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never)
                            
                            TextField("Billing Fax", text: $billingFax)
                                .keyboardType(.phonePad)
                        }
                    }
                }
                
                Section("Location Reminders") {
                    Toggle("Enable Visit Reminders", isOn: $enableReminders)
                    
                    if enableReminders {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Reminder Radius: \(Int(geofenceRadius))m")
                                .font(.subheadline)
                            
                            Slider(value: $geofenceRadius, in: 50...500, step: 25)
                            
                            Text("You'll be reminded when entering this radius around the provider's location.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 100)
                }
                
                if let error = geocodeError {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Edit Provider")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveProvider()
                    }
                    .disabled(name.isEmpty || isGeocoding)
                }
            }
            .delayedLoadingOverlay(isLoading: isGeocoding, delay: 2.0, message: "Finding location...", style: .ring)
            .sheet(isPresented: $showingScanner) {
                ContactInfoScannerView(mode: .provider) { info in
                    applyScannedInfo(info)
                }
            }
        }
    }
    
    private func applyScannedInfo(_ info: ExtractedContactInfo) {
        if name.isEmpty {
            if !info.organization.isEmpty { name = info.organization }
            else if !info.name.isEmpty { name = info.name }
        }
        if !info.phone.isEmpty && phone.isEmpty { phone = info.phone }
        if !info.fax.isEmpty && fax.isEmpty { fax = info.fax }
        if !info.email.isEmpty && email.isEmpty { email = info.email }
        if !info.website.isEmpty && website.isEmpty { website = info.website }
        if !info.npi.isEmpty && npi.isEmpty { npi = info.npi }
        if !info.address.isEmpty && street1.isEmpty { street1 = info.address }
        if !info.city.isEmpty && city.isEmpty { city = info.city }
        if !info.state.isEmpty && state.isEmpty { state = info.state }
        if !info.zipCode.isEmpty && zipCode.isEmpty { zipCode = info.zipCode }
    }
    
    private func saveProvider() {
        provider.name = name
        provider.providerType = providerType
        provider.specialty = specialty
        provider.website = website.isEmpty ? nil : website
        provider.fax = fax.isEmpty ? nil : fax
        provider.npi = npi.isEmpty ? nil : npi
        provider.taxId = taxId.isEmpty ? nil : taxId
        provider.licenseNumber = licenseNumber.isEmpty ? nil : licenseNumber
        provider.notes = notes.isEmpty ? nil : notes
        provider.updatedAt = Date()
        
        // Update phones
        if !phone.isEmpty {
            if provider.phones.isEmpty {
                provider.phones = [PhoneNumber(number: phone, isPrimary: true)]
            } else {
                provider.phones[0].number = phone
            }
        } else {
            provider.phones = []
        }
        
        // Update emails
        provider.emails = email.isEmpty ? [] : [email]
        
        // Update reminder settings
        provider.reminderSettings.isEnabled = enableReminders
        provider.reminderSettings.geofenceRadius = geofenceRadius
        
        // Build address
        if !street1.isEmpty || !city.isEmpty || !state.isEmpty || !zipCode.isEmpty {
            var address = provider.address ?? Address(street1: street1, city: city, state: state, zipCode: zipCode)
            address.street1 = street1
            address.street2 = street2.isEmpty ? nil : street2
            address.city = city
            address.state = state
            address.zipCode = zipCode
            provider.address = address
        } else {
            provider.address = nil
        }
        
        // Build billing address
        if !billingStreet1.isEmpty || !billingCity.isEmpty || !billingState.isEmpty || !billingZipCode.isEmpty {
            var bAddr = provider.billingAddress ?? Address(type: .billing, street1: billingStreet1, city: billingCity, state: billingState, zipCode: billingZipCode)
            bAddr.street1 = billingStreet1
            bAddr.street2 = billingStreet2.isEmpty ? nil : billingStreet2
            bAddr.city = billingCity
            bAddr.state = billingState
            bAddr.zipCode = billingZipCode
            provider.billingAddress = bAddr
        } else {
            provider.billingAddress = nil
        }
        
        // Billing contact
        provider.billingPhone = billingPhone.isEmpty ? nil : billingPhone
        provider.billingEmail = billingEmail.isEmpty ? nil : billingEmail
        provider.billingFax = billingFax.isEmpty ? nil : billingFax
        
        // Geocode if address exists
        if provider.address != nil {
            isGeocoding = true
            geocodeError = nil
            var providerCopy = provider
            
            Task { @MainActor in
                let success = await LocationReminderService.shared.geocodeAndUpdateProvider(&providerCopy)
                isGeocoding = false
                
                if !success && enableReminders {
                    geocodeError = "Could not find location for address. Reminders may not work."
                }
                
                provider.address = providerCopy.address
                patientDataService.saveProvider(provider)
                onSave()
                
                if success && enableReminders && provider.isGeofenceActive {
                    LocationReminderService.shared.startMonitoringProvider(provider)
                } else {
                    LocationReminderService.shared.stopMonitoringProvider(provider)
                }
                
                dismiss()
            }
        } else {
            patientDataService.saveProvider(provider)
            onSave()
            dismiss()
        }
    }
}

// MARK: - Provider Detail View

struct ProviderDetailView: View {
    @EnvironmentObject var patientDataService: PatientDataService
    
    let provider: Provider
    
    @State private var showingEditSheet = false
    @State private var showingReminderSettings = false
    @State private var localProvider: Provider
    
    init(provider: Provider) {
        self.provider = provider
        _localProvider = State(initialValue: provider)
    }
    
    var body: some View {
        List {
            // Header
            Section {
                providerHeader
            }
            
            // Contact Info
            Section("Contact") {
                if let phone = localProvider.primaryPhone {
                    Button {
                        callPhone(phone)
                    } label: {
                        Label(formatPhone(phone), systemImage: "phone.fill")
                    }
                }
                
                if let faxNum = localProvider.fax, !faxNum.isEmpty {
                    Label(formatPhone(faxNum), systemImage: "fax")
                        .foregroundColor(.primary)
                }
                
                if let email = localProvider.primaryEmail {
                    Button {
                        emailProvider(email)
                    } label: {
                        Label(email, systemImage: "envelope.fill")
                    }
                }
                
                if let website = localProvider.website {
                    Link(destination: URL(string: website.hasPrefix("http") ? website : "https://\(website)") ?? URL(string: "https://")!) {
                        Label(website, systemImage: "globe")
                    }
                }
            }
            
            // Address & Map
            if let address = localProvider.address {
                Section("Location") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(address.formatted)
                            .font(.subheadline)
                        
                        if localProvider.hasLocation {
                            // Mini map preview
                            MiniMapView(coordinate: localProvider.coordinate!)
                                .frame(height: 150)
                                .cornerRadius(10)
                            
                            Button {
                                openInMaps()
                            } label: {
                                Label("Get Directions", systemImage: "arrow.triangle.turn.up.right.diamond")
                            }
                        }
                    }
                }
            }
            
            // Reminder Settings
            Section("Visit Reminders") {
                Toggle("Enable Reminders", isOn: $localProvider.isGeofenceActive)
                    .onChange(of: localProvider.isGeofenceActive) { _, newValue in
                        updateGeofence(enabled: newValue)
                    }
                
                if localProvider.isGeofenceActive {
                    Button {
                        showingReminderSettings = true
                    } label: {
                        HStack {
                            Text("Reminder Settings")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                    }
                    .foregroundColor(.primary)
                    
                    if localProvider.hasLocation {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Location monitoring active")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("Address needs geocoding")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            
            // Visit History
            Section("Visit History") {
                HStack {
                    Text("Total Visits")
                    Spacer()
                    Text("\(localProvider.visitCount)")
                        .foregroundColor(.secondary)
                }
                
                if let lastVisit = localProvider.lastVisitDate {
                    HStack {
                        Text("Last Visit")
                        Spacer()
                        Text(lastVisit, style: .date)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            // Business Info
            if localProvider.npi != nil || localProvider.taxId != nil || localProvider.licenseNumber != nil {
                Section("Business Information") {
                    if let npi = localProvider.npi {
                        HStack {
                            Text("NPI")
                            Spacer()
                            Text(npi)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    if let taxId = localProvider.taxId {
                        HStack {
                            Text("Tax ID / EIN")
                            Spacer()
                            Text(taxId)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    if let license = localProvider.licenseNumber {
                        HStack {
                            Text("License #")
                            Spacer()
                            Text(license)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            
            // Billing Contact
            if localProvider.billingAddress != nil || localProvider.billingPhone != nil || localProvider.billingEmail != nil || localProvider.billingFax != nil {
                Section("Billing Contact") {
                    if let bAddr = localProvider.billingAddress {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(bAddr.formatted)
                                .font(.subheadline)
                        }
                    }
                    
                    if let bPhone = localProvider.billingPhone, !bPhone.isEmpty {
                        Button {
                            callPhone(bPhone)
                        } label: {
                            Label(formatPhone(bPhone), systemImage: "phone")
                        }
                    }
                    
                    if let bEmail = localProvider.billingEmail, !bEmail.isEmpty {
                        Button {
                            emailProvider(bEmail)
                        } label: {
                            Label(bEmail, systemImage: "envelope")
                        }
                    }
                    
                    if let bFax = localProvider.billingFax, !bFax.isEmpty {
                        Label(formatPhone(bFax), systemImage: "fax")
                            .foregroundColor(.primary)
                    }
                }
            }
        }
        .navigationTitle("Provider")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") {
                    showingEditSheet = true
                }
            }
        }
        .sheet(isPresented: $showingReminderSettings) {
            ReminderSettingsView(settings: $localProvider.reminderSettings) {
                saveProvider()
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            EditProviderView(provider: $localProvider) {
                saveProvider()
            }
            .environmentObject(patientDataService)
        }
    }
    
    private var providerHeader: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 60, height: 60)
                
                Image(systemName: localProvider.providerType.icon)
                    .font(.title2)
                    .foregroundColor(.accentColor)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(localProvider.name)
                    .font(.title3)
                    .fontWeight(.bold)
                
                Text(localProvider.providerType.rawValue)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                if let specialty = localProvider.specialty {
                    Text(specialty.rawValue)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.1))
                        .cornerRadius(4)
                }
            }
        }
        .padding(.vertical, 8)
    }
    
    private func updateGeofence(enabled: Bool) {
        if enabled {
            LocationReminderService.shared.startMonitoringProvider(localProvider)
        } else {
            LocationReminderService.shared.stopMonitoringProvider(localProvider)
        }
        saveProvider()
    }
    
    private func saveProvider() {
        patientDataService.saveProvider(localProvider)
    }
    
    private func callPhone(_ phone: String) {
        let digits = phone.filter { $0.isNumber }
        if let url = URL(string: "tel://\(digits)") {
            UIApplication.shared.open(url)
        }
    }
    
    private func emailProvider(_ email: String) {
        if let url = URL(string: "mailto:\(email)") {
            UIApplication.shared.open(url)
        }
    }
    
    private func formatPhone(_ phone: String) -> String {
        let digits = phone.filter { $0.isNumber }
        guard digits.count == 10 else { return phone }
        return "(\(digits.prefix(3))) \(digits.dropFirst(3).prefix(3))-\(digits.dropFirst(6))"
    }
    
    private func openInMaps() {
        guard let coordinate = localProvider.coordinate else { return }
        let placemark = MKPlacemark(coordinate: coordinate)
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.name = localProvider.name
        mapItem.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
    }
}

// MARK: - Mini Map View

struct MiniMapView: View {
    let coordinate: CLLocationCoordinate2D

    private var initialPosition: MapCameraPosition {
        .region(MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
        ))
    }

    var body: some View {
        Map(initialPosition: initialPosition) {
            Marker("", coordinate: coordinate)
                .tint(Color.accentColor)
        }
        .disabled(true)
    }
}

// MARK: - Reminder Settings View

struct ReminderSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var settings: ProviderReminderSettings
    let onSave: () -> Void
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Timing") {
                    Toggle("Remind on Arrival", isOn: $settings.remindOnArrival)
                    Toggle("Remind on Departure", isOn: $settings.remindOnDeparture)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Detection Radius: \(Int(settings.geofenceRadius))m")
                            .font(.subheadline)
                        Slider(value: $settings.geofenceRadius, in: 50...500, step: 25)
                    }
                }
                
                Section("What to Remember") {
                    Toggle("📸 Take photos of documents", isOn: $settings.remindToPhotograph)
                    Toggle("📋 Get procedure codes (CPT)", isOn: $settings.remindForProcedureCodes)
                    Toggle("🏥 Get diagnosis codes (ICD-10)", isOn: $settings.remindForDiagnosisCodes)
                    Toggle("📄 Request itemized bill", isOn: $settings.remindForItemizedBill)
                    Toggle("📝 Get follow-up documentation", isOn: $settings.remindForFollowUpDocs)
                }
                
                Section("Custom Message") {
                    TextEditor(text: $settings.reminderMessage)
                        .frame(minHeight: 100)
                }
            }
            .navigationTitle("Reminder Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave()
                        dismiss()
                    }
                }
            }
        }
    }
}
