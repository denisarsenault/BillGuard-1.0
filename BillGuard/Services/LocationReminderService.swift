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
import MapKit

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
        // Phase 2 (opt-in): detect arrival at *any* health facility, not just
        // saved providers, via the OS visit-monitoring API.
        if isGenericDetectionEnabled {
            manager.startMonitoringVisits()
        }
    }

    // MARK: - Generic facility detection (opt-in)

    private let genericDetectionKey = "genericFacilityDetectionEnabled"

    /// When on, BillGuard also coaches on arrival at unsaved hospitals/pharmacies
    /// (OS visit monitoring + MapKit POI lookup). Off by default — coarser and
    /// more battery-hungry than the saved-provider geofences.
    var isGenericDetectionEnabled: Bool {
        UserDefaults.standard.bool(forKey: genericDetectionKey)
    }

    func setGenericFacilityDetection(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: genericDetectionKey)
        if enabled {
            locationManager?.startMonitoringVisits()
        } else {
            locationManager?.stopMonitoringVisits()
        }
    }

    /// De-dupes repeat visit callbacks for the same spot within a session.
    private var coachedVisitKeys: Set<String> = []
    
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

    nonisolated func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        // Only coach on arrival (still at the place): a live visit has no
        // departure date yet.
        guard visit.departureDate == Date.distantFuture else { return }
        let coordinate = visit.coordinate
        Task { @MainActor [weak self] in
            self?.handleVisit(at: coordinate)
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
        // In-app "balloon" coaching: shows now if the app is open, or as soon as
        // the user opens it after tapping the arrival notification.
        ArrivalCoach.shared.present(facilityName: provider.name, providerId: provider.id,
                                    mode: .arrival, settings: provider.reminderSettings)

        // Update visit count
        var updatedProvider = provider
        updatedProvider.visitCount += 1
        updatedProvider.lastVisitDate = Date()
        monitoredProviders[identifier] = updatedProvider

        // NOTE: the old fire-and-forget next-day reminder is retired. Follow-up
        // is now tracked as tasks created from the departure confirmation
        // balloon (see handleRegionExit → FollowUpStore).
    }


    private func handleRegionExit(identifier: String) {
        guard let provider = monitoredProviders[identifier] else { return }
        sendDepartureNotification(for: provider)
        // Departure "balloon": confirm what they got; anything left becomes a
        // tracked follow-up task.
        ArrivalCoach.shared.present(facilityName: provider.name, providerId: provider.id,
                                    mode: .departure, settings: provider.reminderSettings)
    }

    // MARK: - Generic facility visit handling (opt-in)

    private func handleVisit(at coordinate: CLLocationCoordinate2D) {
        guard isGenericDetectionEnabled else { return }
        guard CLLocationCoordinate2DIsValid(coordinate) else { return }
        let key = String(format: "%.4f,%.4f", coordinate.latitude, coordinate.longitude)
        guard !coachedVisitKeys.contains(key) else { return }

        Task { @MainActor [weak self] in
            guard let self else { return }
            // Look for a hospital/pharmacy POI essentially on top of the visit.
            let request = MKLocalPointsOfInterestRequest(center: coordinate, radius: 150)
            request.pointOfInterestFilter = MKPointOfInterestFilter(including: [.hospital, .pharmacy])
            guard let response = try? await MKLocalSearch(request: request).start() else { return }

            let here = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            let nearest = response.mapItems.compactMap { item -> (String, CLLocationDistance)? in
                guard let loc = item.placemark.location else { return nil }
                return (item.name ?? "a health facility", loc.distance(from: here))
            }.min(by: { $0.1 < $1.1 })

            guard let nearest, nearest.1 < 120 else { return }
            self.coachedVisitKeys.insert(key)
            // Skip if a saved-provider geofence already covers this spot.
            guard !self.monitoredProviders.values.contains(where: { $0.name == nearest.0 }) else { return }
            self.sendGenericArrivalNotification(facilityName: nearest.0)
            ArrivalCoach.shared.present(facilityName: nearest.0, settings: nil)
        }
    }

    private func sendGenericArrivalNotification(facilityName: String) {
        guard canSendNotifications else { return }
        let content = UNMutableNotificationContent()
        content.title = "📍 At \(facilityName)?"
        content.subtitle = "Medical Visit Reminder"
        content.body = "Tap for the questions to ask at the front desk."
        content.sound = .default
        content.categoryIdentifier = "PROVIDER_ARRIVAL"
        content.userInfo = ["facilityName": facilityName, "type": "genericArrival"]
        let request = UNNotificationRequest(
            identifier: "genericArrival_\(Date().timeIntervalSince1970)",
            content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
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

// MARK: - Arrival Coaching (balloon prompts)

enum CoachMode { case arrival, departure }

/// Drives the in-app "balloon" that coaches the user at a health facility.
/// On arrival it lists what to ask; on departure it confirms what they got and
/// turns anything still outstanding into follow-up tasks. Observed by
/// `BalloonCoachOverlay`. Mirrors MapMe's announcement-service pattern.
@MainActor
final class ArrivalCoach: ObservableObject {
    static let shared = ArrivalCoach()
    private init() {}

    @Published var prompt: ArrivalPrompt?

    /// Geofence/visit entries can fire while the app is terminated (iOS wakes it
    /// in the background). If the user doesn't open the app for a while, the
    /// prompt is stale — don't pop a balloon hours after the fact.
    private let maxAge: TimeInterval = 2 * 60 * 60

    func present(facilityName: String, providerId: String? = nil,
                 mode: CoachMode = .arrival, settings: ProviderReminderSettings?) {
        prompt = ArrivalPrompt(facilityName: facilityName, providerId: providerId, mode: mode,
                               questions: ArrivalPrompt.frontDeskQuestions(for: settings))
    }

    func dismiss() { prompt = nil }

    /// Call when the overlay appears / app foregrounds to drop stale prompts.
    func expireIfStale() {
        if let p = prompt, Date().timeIntervalSince(p.createdAt) > maxAge {
            prompt = nil
        }
    }
}

struct ArrivalPrompt: Identifiable {
    let id = UUID()
    let facilityName: String
    var providerId: String? = nil
    var mode: CoachMode = .arrival
    let createdAt = Date()
    var questions: [CoachQuestion]

    /// The front-desk question script. Honors the saved provider's reminder
    /// toggles when present; otherwise shows the full default script.
    static func frontDeskQuestions(for settings: ProviderReminderSettings?) -> [CoachQuestion] {
        var q: [CoachQuestion] = []
        q.append(CoachQuestion(icon: "doc.text.magnifyingglass",
                               text: "Ask for an itemized bill with CPT codes",
                               detail: "The line-by-line statement — not just the summary.",
                               kind: .itemizedBill))
        if settings?.remindForDiagnosisCodes ?? true {
            q.append(CoachQuestion(icon: "stethoscope",
                                   text: "Get today's diagnosis (ICD-10) codes",
                                   detail: "They rarely show on the bill — ask them to note them.",
                                   kind: .diagnosisCodes))
        }
        q.append(CoachQuestion(icon: "checkmark.shield",
                               text: "Confirm this provider is in-network",
                               detail: "Have them verify against your plan before service.",
                               kind: .inNetwork))
        q.append(CoachQuestion(icon: "dollarsign.circle",
                               text: "If self-pay: request a Good Faith Estimate",
                               detail: "Your right before scheduled care (No Surprises Act).",
                               kind: .goodFaithEstimate))
        if settings?.remindToPhotograph ?? true {
            q.append(CoachQuestion(icon: "camera",
                                   text: "Photograph every form you sign",
                                   kind: .documents))
        }
        q.append(CoachQuestion(icon: "phone",
                               text: "Get the billing department's direct number",
                               detail: "For itemized-bill and records requests later.",
                               kind: .billingContact))
        return q
    }
}

struct CoachQuestion: Identifiable {
    let id = UUID()
    let icon: String
    let text: String
    var detail: String? = nil
    var kind: FollowUpKind? = nil
}

// MARK: - Follow-up Task Engine

/// The kinds of follow-up BillGuard tracks after a visit. Each carries its own
/// icon and a default due window — several of which are real legal clocks.
enum FollowUpKind: String, Codable, CaseIterable {
    case itemizedBill, procedureCodes, diagnosisCodes, inNetwork
    case goodFaithEstimate, documents, billingContact, custom

    var title: String {
        switch self {
        case .itemizedBill:     return "Request an itemized bill"
        case .procedureCodes:   return "Get the procedure (CPT) codes"
        case .diagnosisCodes:   return "Get the diagnosis (ICD-10) codes"
        case .inNetwork:        return "Confirm the provider was in-network"
        case .goodFaithEstimate:return "Request a Good Faith Estimate"
        case .documents:        return "Save the visit documents"
        case .billingContact:   return "Get the billing department's number"
        case .custom:           return "Follow up"
        }
    }
    var icon: String {
        switch self {
        case .itemizedBill:     return "doc.text.magnifyingglass"
        case .procedureCodes:   return "list.bullet.rectangle"
        case .diagnosisCodes:   return "stethoscope"
        case .inNetwork:        return "checkmark.shield"
        case .goodFaithEstimate:return "dollarsign.circle"
        case .documents:        return "camera"
        case .billingContact:   return "phone"
        case .custom:           return "flag"
        }
    }
    /// Days from creation the follow-up should be nudged. Itemized bill /
    /// records track toward the ~30-day HIPAA response window; most others get
    /// a gentle two-week nudge.
    var defaultDueDays: Int {
        switch self {
        case .itemizedBill, .diagnosisCodes, .procedureCodes: return 14
        case .goodFaithEstimate: return 3
        case .inNetwork, .billingContact, .documents, .custom: return 7
        }
    }
}

struct FollowUpTask: Identifiable, Codable, Hashable {
    var id: String = UUID().uuidString
    var kind: FollowUpKind
    var title: String
    var providerName: String?
    var providerId: String?
    var createdAt: Date = Date()
    var dueDate: Date?
    var isCompleted: Bool = false
    var completedAt: Date?
    var note: String?

    var isOverdue: Bool {
        guard !isCompleted, let dueDate else { return false }
        return dueDate < Date()
    }
}

/// Persisted, observable store of follow-up tasks. UserDefaults-backed today
/// (matches PatientDataService's local cache); CloudKit sync is a later step.
/// Each task with a due date also schedules a single escalating local
/// notification, cancelled when the task is completed or removed — this
/// replaces the old fire-and-forget next-day reminder.
@MainActor
final class FollowUpStore: ObservableObject {
    static let shared = FollowUpStore()

    @Published private(set) var tasks: [FollowUpTask] = []

    private let storageKey = "followUpTasks"

    private init() { load() }

    var openTasks: [FollowUpTask] {
        tasks.filter { !$0.isCompleted }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }
    var openCount: Int { tasks.lazy.filter { !$0.isCompleted }.count }

    /// Create a task, skipping if an identical open one already exists for the
    /// same provider + kind (no duplicate nags).
    @discardableResult
    func addUnique(kind: FollowUpKind, providerName: String?, providerId: String?,
                   title: String? = nil, note: String? = nil) -> FollowUpTask? {
        let exists = tasks.contains { !$0.isCompleted && $0.kind == kind
            && $0.providerName == providerName && $0.providerId == providerId }
        guard !exists else { return nil }
        var task = FollowUpTask(kind: kind, title: title ?? kind.title,
                                providerName: providerName, providerId: providerId, note: note)
        task.dueDate = Calendar.current.date(byAdding: .day, value: kind.defaultDueDays, to: Date())
        tasks.append(task)
        scheduleReminder(for: task)
        save()
        return task
    }

    func complete(_ id: String) {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[i].isCompleted = true
        tasks[i].completedAt = Date()
        cancelReminder(id: id)
        save()
    }

    func remove(_ id: String) {
        tasks.removeAll { $0.id == id }
        cancelReminder(id: id)
        save()
    }

    func clearCompleted() {
        tasks.removeAll { $0.isCompleted }
        save()
    }

    // MARK: Reminders

    private func scheduleReminder(for task: FollowUpTask) {
        guard let due = task.dueDate else { return }
        let content = UNMutableNotificationContent()
        content.title = "📋 Follow-up"
        content.body = [task.title, task.providerName].compactMap { $0 }.joined(separator: " — ")
        content.sound = .default
        content.userInfo = ["taskId": task.id, "type": "followupTask"]

        var comps = Calendar.current.dateComponents([.year, .month, .day], from: due)
        comps.hour = 9
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(identifier: "task_\(task.id)", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    private func cancelReminder(id: String) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ["task_\(id)"])
    }

    // MARK: Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([FollowUpTask].self, from: data) else { return }
        tasks = decoded
    }
    private func save() {
        if let data = try? JSONEncoder().encode(tasks) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}
