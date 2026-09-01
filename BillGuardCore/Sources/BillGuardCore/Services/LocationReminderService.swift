//
//  LocationReminderService.swift
//  BillGuard
//
//  Manages location-based reminders for provider visits
//  Handles geofencing, notifications, and geocoding
//

import Foundation
import CoreLocation
import UserNotifications
import Combine

// MARK: - Location Reminder Service

@MainActor
final class LocationReminderService: NSObject, ObservableObject {
    // Singleton - accessed only from MainActor context
    static let shared = LocationReminderService()
    
    // MARK: - Published Properties
    
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var notificationStatus: UNAuthorizationStatus = .notDetermined
    @Published var isMonitoring: Bool = false
    @Published var activeGeofences: Set<String> = []
    @Published var lastError: String?
    
    // MARK: - Private Properties
    
    private var locationManager: CLLocationManager?
    private var monitoredProviders: [String: Provider] = [:]
    
    // MARK: - Constants
    
    private let maxGeofences = 20 // iOS limit
    private let defaultRadius: CLLocationDistance = 100 // meters
    
    // MARK: - Initialization
    
    private override init() {
        super.init()
        // Defer setup to avoid issues during static initialization
    }
    
    /// Call this to initialize the service when the app is ready
    func initialize() {
        guard locationManager == nil else { return }
        setupLocationManager()
        checkAuthorizationStatus()
    }
    
    private func setupLocationManager() {
        let manager = CLLocationManager()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.allowsBackgroundLocationUpdates = false
        locationManager = manager
    }
    
    // MARK: - Authorization
    
    func requestLocationAuthorization() {
        initialize()
        locationManager?.requestWhenInUseAuthorization()
    }
    
    func requestAlwaysAuthorization() {
        initialize()
        locationManager?.requestAlwaysAuthorization()
    }
    

    func requestNotificationAuthorization() async -> Bool {
        do {
            let center = UNUserNotificationCenter.current()
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            checkNotificationStatus()
            return granted
        } catch {
            lastError = "Failed to request notification permission: \(error.localizedDescription)"
            return false
        }
    }
    

    private func checkAuthorizationStatus() {
        if let manager = locationManager {
            authorizationStatus = manager.authorizationStatus
        }
        checkNotificationStatus()
    }
    

    private func checkNotificationStatus() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { [weak self] settings in
            // Capture the value before crossing isolation boundary to avoid data race
            let status = settings.authorizationStatus
            Task { @MainActor in
                self?.notificationStatus = status
            }
        }
    }
    

    var canUseGeofencing: Bool {
        authorizationStatus == .authorizedAlways && CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self)
    }
    

    var canSendNotifications: Bool {
        notificationStatus == .authorized
    }
    
    // MARK: - Geocoding
    

    func geocodeAddress(_ address: Address) async -> CLLocationCoordinate2D? {
        let addressString = address.fullAddressForGeocoding
        let geocoder = CLGeocoder()
        
        do {
            let placemarks = try await geocoder.geocodeAddressString(addressString)
            if let location = placemarks.first?.location {
                return location.coordinate
            }
        } catch {
            lastError = "Geocoding failed: \(error.localizedDescription)"
        }
        
        return nil
    }
    

    func geocodeAndUpdateProvider(_ provider: inout Provider) async -> Bool {
        guard var address = provider.address else { return false }
        
        if let coordinate = await geocodeAddress(address) {
            address.latitude = coordinate.latitude
            address.longitude = coordinate.longitude
            provider.address = address
            return true
        }
        
        return false
    }
    
    // MARK: - Geofencing
    

    func startMonitoringProvider(_ provider: Provider) {
        initialize()
        
        guard canUseGeofencing else {
            lastError = "Location permission required for geofencing"
            return
        }
        
        guard let coordinate = provider.coordinate else {
            lastError = "Provider has no location coordinates"
            return
        }
        
        guard provider.isGeofenceActive && provider.reminderSettings.isEnabled else {
            return
        }
        
        // Check if we're at the limit
        if activeGeofences.count >= maxGeofences {
            lastError = "Maximum geofence limit reached (\(maxGeofences))"
            return
        }
        
        let region = CLCircularRegion(
            center: coordinate,
            radius: provider.reminderSettings.geofenceRadius,
            identifier: provider.geofenceIdentifier
        )
        
        region.notifyOnEntry = provider.reminderSettings.remindOnArrival
        region.notifyOnExit = provider.reminderSettings.remindOnDeparture
        
        locationManager?.startMonitoring(for: region)
        monitoredProviders[provider.geofenceIdentifier] = provider
        activeGeofences.insert(provider.geofenceIdentifier)
        isMonitoring = true
    }
    

    func stopMonitoringProvider(_ provider: Provider) {
        let identifier = provider.geofenceIdentifier
        
        if let region = locationManager?.monitoredRegions.first(where: { $0.identifier == identifier }) {
            locationManager?.stopMonitoring(for: region)
        }
        
        monitoredProviders.removeValue(forKey: identifier)
        activeGeofences.remove(identifier)
        
        if activeGeofences.isEmpty {
            isMonitoring = false
        }
    }
    

    func stopAllMonitoring() {
        if let regions = locationManager?.monitoredRegions {
            for region in regions {
                locationManager?.stopMonitoring(for: region)
            }
        }
        
        monitoredProviders.removeAll()
        activeGeofences.removeAll()
        isMonitoring = false
    }
    

    func updateMonitoredProviders(_ providers: [Provider]) {
        initialize()
        
        // Stop monitoring removed providers
        let newIdentifiers = Set(providers.filter { $0.isGeofenceActive && $0.hasLocation }.map { $0.geofenceIdentifier })
        let toRemove = activeGeofences.subtracting(newIdentifiers)
        
        for identifier in toRemove {
            if let region = locationManager?.monitoredRegions.first(where: { $0.identifier == identifier }) {
                locationManager?.stopMonitoring(for: region)
            }
            monitoredProviders.removeValue(forKey: identifier)
            activeGeofences.remove(identifier)
        }
        
        // Start monitoring new providers
        for provider in providers {
            if provider.isGeofenceActive && provider.hasLocation && !activeGeofences.contains(provider.geofenceIdentifier) {
                startMonitoringProvider(provider)
            }
        }
    }
    
    // MARK: - Notifications
    

    private func sendArrivalNotification(for provider: Provider) {
        guard canSendNotifications else { return }
        
        let settings = provider.reminderSettings
        
        let content = UNMutableNotificationContent()
        content.title = "📍 Arrived at \(provider.name)"
        content.subtitle = "Medical Visit Reminder"
        content.body = buildReminderMessage(for: settings, isArrival: true)
        content.sound = .default
        content.categoryIdentifier = "PROVIDER_ARRIVAL"
        content.userInfo = [
            "providerId": provider.id,
            "providerName": provider.name,
            "type": "arrival"
        ]
        
        let request = UNNotificationRequest(
            identifier: "arrival_\(provider.id)_\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil // Immediate
        )
        
        let center = UNUserNotificationCenter.current()
        center.add(request)
    }
    

    private func sendDepartureNotification(for provider: Provider) {
        guard canSendNotifications else { return }
        
        let settings = provider.reminderSettings
        
        let content = UNMutableNotificationContent()
        content.title = "👋 Leaving \(provider.name)"
        content.subtitle = "Don't Forget!"
        content.body = buildDepartureMessage(for: settings)
        content.sound = .default
        content.categoryIdentifier = "PROVIDER_DEPARTURE"
        content.userInfo = [
            "providerId": provider.id,
            "providerName": provider.name,
            "type": "departure"
        ]
        
        let request = UNNotificationRequest(
            identifier: "departure_\(provider.id)_\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        
        let center = UNUserNotificationCenter.current()
        center.add(request)
    }
    
    private func buildReminderMessage(for settings: ProviderReminderSettings, isArrival: Bool) -> String {
        var items: [String] = []
        
        if settings.remindToPhotograph {
            items.append("📸 Take photos of all documents")
        }
        if settings.remindForProcedureCodes {
            items.append("📋 Request procedure codes (CPT)")
        }
        if settings.remindForDiagnosisCodes {
            items.append("🏥 Ask for diagnosis codes (ICD-10)")
        }
        if settings.remindForItemizedBill {
            items.append("📄 Request itemized bill")
        }
        if settings.remindForFollowUpDocs {
            items.append("📝 Get follow-up documentation")
        }
        
        if items.isEmpty {
            return settings.reminderMessage
        }
        
        return items.joined(separator: "\n")
    }
    
    private func buildDepartureMessage(for settings: ProviderReminderSettings) -> String {
        var items: [String] = []
        
        if settings.remindToPhotograph {
            items.append("Did you photograph all documents?")
        }
        if settings.remindForProcedureCodes {
            items.append("Did you get procedure codes?")
        }
        if settings.remindForItemizedBill {
            items.append("Did you request an itemized bill?")
        }
        
        if items.isEmpty {
            return "Make sure you have all your documentation!"
        }
        
        return items.joined(separator: "\n")
    }
    
    // MARK: - Notification Actions Setup
    

    func setupNotificationCategories() {
        // Arrival actions
        let takePhotoAction = UNNotificationAction(
            identifier: "TAKE_PHOTO",
            title: "📸 Open Camera",
            options: .foreground
        )
        
        let viewChecklistAction = UNNotificationAction(
            identifier: "VIEW_CHECKLIST",
            title: "📋 View Checklist",
            options: .foreground
        )
        
        let dismissAction = UNNotificationAction(
            identifier: "DISMISS",
            title: "Dismiss",
            options: .destructive
        )
        
        let arrivalCategory = UNNotificationCategory(
            identifier: "PROVIDER_ARRIVAL",
            actions: [takePhotoAction, viewChecklistAction, dismissAction],
            intentIdentifiers: [],
            options: .customDismissAction
        )
        
        // Departure actions
        let confirmAction = UNNotificationAction(
            identifier: "CONFIRM_COMPLETE",
            title: "✅ All Done",
            options: []
        )
        
        let addBillAction = UNNotificationAction(
            identifier: "ADD_BILL",
            title: "➕ Add Bill",
            options: .foreground
        )
        
        let departureCategory = UNNotificationCategory(
            identifier: "PROVIDER_DEPARTURE",
            actions: [confirmAction, addBillAction, dismissAction],
            intentIdentifiers: [],
            options: .customDismissAction
        )
        
        let center = UNUserNotificationCenter.current()
        center.setNotificationCategories([arrivalCategory, departureCategory])
    }
    
    // MARK: - Schedule Follow-up Reminder
    

    func scheduleFollowUpReminder(for provider: Provider, visitDate: Date) {
        guard canSendNotifications else { return }
        
        // Schedule reminder for next day at 9 AM
        var components = Calendar.current.dateComponents([.year, .month, .day], from: visitDate)
        components.day! += 1
        components.hour = 9
        components.minute = 0
        
        let content = UNMutableNotificationContent()
        content.title = "📋 Follow-up: \(provider.name)"
        content.body = "Did you receive all documentation from yesterday's visit? Remember to:\n• Save any procedure codes\n• Store itemized bills\n• Note any pending items"
        content.sound = .default
        content.userInfo = ["providerId": provider.id, "type": "followup"]
        
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        
        let request = UNNotificationRequest(
            identifier: "followup_\(provider.id)_\(visitDate.timeIntervalSince1970)",
            content: content,
            trigger: trigger
        )
        
        let center = UNUserNotificationCenter.current()
        center.add(request)
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationReminderService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor [weak self] in
            self?.handleAuthorizationChange(status: status)
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard let circularRegion = region as? CLCircularRegion else { return }
        let identifier = String(circularRegion.identifier)
        
        Task { @MainActor [weak self] in
            self?.handleRegionEntry(identifier: identifier)
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        guard let circularRegion = region as? CLCircularRegion else { return }
        let identifier = String(circularRegion.identifier)
        
        Task { @MainActor [weak self] in
            self?.handleRegionExit(identifier: identifier)
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        let errorMessage = String(error.localizedDescription)
        Task { @MainActor [weak self] in
            self?.lastError = "Geofence monitoring failed: \(errorMessage)"
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let errorMessage = String(error.localizedDescription)
        Task { @MainActor [weak self] in
            self?.lastError = "Location error: \(errorMessage)"
        }
    }
}

// MARK: - MainActor Helper Methods

extension LocationReminderService {

    private func handleAuthorizationChange(status: CLAuthorizationStatus) {
        self.authorizationStatus = status
    }
    

    private func handleRegionEntry(identifier: String) {
        guard let provider = monitoredProviders[identifier] else { return }
        
        sendArrivalNotification(for: provider)
        
        // Update visit count
        var updatedProvider = provider
        updatedProvider.visitCount += 1
        updatedProvider.lastVisitDate = Date()
        monitoredProviders[identifier] = updatedProvider
        
        // Schedule follow-up reminder
        scheduleFollowUpReminder(for: provider, visitDate: Date())
    }
    

    private func handleRegionExit(identifier: String) {
        guard let provider = monitoredProviders[identifier] else { return }
        sendDepartureNotification(for: provider)
    }
}

// MARK: - Visit Checklist Item

struct VisitChecklistItem: Identifiable, Codable {
    var id: String = UUID().uuidString
    var title: String
    var isCompleted: Bool = false
    var icon: String
    
    static let defaultChecklist: [VisitChecklistItem] = [
        VisitChecklistItem(title: "Take photo of visit summary", icon: "camera.fill"),
        VisitChecklistItem(title: "Get procedure codes (CPT)", icon: "doc.text.fill"),
        VisitChecklistItem(title: "Get diagnosis codes (ICD-10)", icon: "cross.case.fill"),
        VisitChecklistItem(title: "Request itemized bill", icon: "list.bullet.rectangle"),
        VisitChecklistItem(title: "Note any prescriptions", icon: "pills.fill"),
        VisitChecklistItem(title: "Schedule follow-up if needed", icon: "calendar.badge.plus"),
        VisitChecklistItem(title: "Get provider contact info", icon: "phone.fill"),
        VisitChecklistItem(title: "Confirm insurance was billed", icon: "creditcard.fill")
    ]
}
