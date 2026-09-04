//
//  Address.swift
//  BillGuard
//
//  Address model for patients, providers, and carriers
//

import Foundation
import CoreLocation

// MARK: - Address Type

public enum AddressType: String, Codable, CaseIterable {
    case home = "Home"
    case work = "Work"
    case billing = "Billing"
    case mailing = "Mailing"
    case temporary = "Temporary"
    case other = "Other"
}

// MARK: - Address Model

public struct Address: Codable, Hashable, Identifiable {
    public var id: String
    public var type: AddressType
    public var street1: String
    public var street2: String?
    public var city: String
    public var state: String
    public var zipCode: String
    public var country: String
    public var isPrimary: Bool
    
    // Location coordinates for mapping/geofencing
    public var latitude: Double?
    public var longitude: Double?
    
    public init(
        id: String = UUID().uuidString,
        type: AddressType = .home,
        street1: String,
        street2: String? = nil,
        city: String,
        state: String,
        zipCode: String,
        country: String = "USA",
        isPrimary: Bool = false,
        latitude: Double? = nil,
        longitude: Double? = nil
    ) {
        self.id = id
        self.type = type
        self.street1 = street1
        self.street2 = street2
        self.city = city
        self.state = state
        self.zipCode = zipCode
        self.country = country
        self.isPrimary = isPrimary
        self.latitude = latitude
        self.longitude = longitude
    }
    
    // MARK: - Computed Properties
    
    public var formatted: String {
        var lines: [String] = []
        lines.append(street1)
        if let street2 = street2, !street2.isEmpty {
            lines.append(street2)
        }
        lines.append("\(city), \(state) \(zipCode)")
        if country != "USA" {
            lines.append(country)
        }
        return lines.joined(separator: "\n")
    }
    
    public var singleLine: String {
        var parts: [String] = [street1]
        if let street2 = street2, !street2.isEmpty {
            parts.append(street2)
        }
        parts.append(city)
        parts.append(state)
        parts.append(zipCode)
        return parts.joined(separator: ", ")
    }
    
    public var cityStateZip: String {
        "\(city), \(state) \(zipCode)"
    }
    
    public var hasCoordinates: Bool {
        latitude != nil && longitude != nil
    }
    
    public var coordinate: CLLocationCoordinate2D? {
        guard let lat = latitude, let lon = longitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
    
    // For geocoding lookup
    public var fullAddressForGeocoding: String {
        "\(street1), \(city), \(state) \(zipCode), \(country)"
    }
}

// MARK: - US States

public struct USState {
    public let name: String
    public let abbreviation: String
    
    public static let all: [USState] = [
        USState(name: "Alabama", abbreviation: "AL"),
        USState(name: "Alaska", abbreviation: "AK"),
        USState(name: "Arizona", abbreviation: "AZ"),
        USState(name: "Arkansas", abbreviation: "AR"),
        USState(name: "California", abbreviation: "CA"),
        USState(name: "Colorado", abbreviation: "CO"),
        USState(name: "Connecticut", abbreviation: "CT"),
        USState(name: "Delaware", abbreviation: "DE"),
        USState(name: "Florida", abbreviation: "FL"),
        USState(name: "Georgia", abbreviation: "GA"),
        USState(name: "Hawaii", abbreviation: "HI"),
        USState(name: "Idaho", abbreviation: "ID"),
        USState(name: "Illinois", abbreviation: "IL"),
        USState(name: "Indiana", abbreviation: "IN"),
        USState(name: "Iowa", abbreviation: "IA"),
        USState(name: "Kansas", abbreviation: "KS"),
        USState(name: "Kentucky", abbreviation: "KY"),
        USState(name: "Louisiana", abbreviation: "LA"),
        USState(name: "Maine", abbreviation: "ME"),
        USState(name: "Maryland", abbreviation: "MD"),
        USState(name: "Massachusetts", abbreviation: "MA"),
        USState(name: "Michigan", abbreviation: "MI"),
        USState(name: "Minnesota", abbreviation: "MN"),
        USState(name: "Mississippi", abbreviation: "MS"),
        USState(name: "Missouri", abbreviation: "MO"),
        USState(name: "Montana", abbreviation: "MT"),
        USState(name: "Nebraska", abbreviation: "NE"),
        USState(name: "Nevada", abbreviation: "NV"),
        USState(name: "New Hampshire", abbreviation: "NH"),
        USState(name: "New Jersey", abbreviation: "NJ"),
        USState(name: "New Mexico", abbreviation: "NM"),
        USState(name: "New York", abbreviation: "NY"),
        USState(name: "North Carolina", abbreviation: "NC"),
        USState(name: "North Dakota", abbreviation: "ND"),
        USState(name: "Ohio", abbreviation: "OH"),
        USState(name: "Oklahoma", abbreviation: "OK"),
        USState(name: "Oregon", abbreviation: "OR"),
        USState(name: "Pennsylvania", abbreviation: "PA"),
        USState(name: "Rhode Island", abbreviation: "RI"),
        USState(name: "South Carolina", abbreviation: "SC"),
        USState(name: "South Dakota", abbreviation: "SD"),
        USState(name: "Tennessee", abbreviation: "TN"),
        USState(name: "Texas", abbreviation: "TX"),
        USState(name: "Utah", abbreviation: "UT"),
        USState(name: "Vermont", abbreviation: "VT"),
        USState(name: "Virginia", abbreviation: "VA"),
        USState(name: "Washington", abbreviation: "WA"),
        USState(name: "West Virginia", abbreviation: "WV"),
        USState(name: "Wisconsin", abbreviation: "WI"),
        USState(name: "Wyoming", abbreviation: "WY"),
        USState(name: "District of Columbia", abbreviation: "DC"),
    ]
    
    public static var abbreviations: [String] {
        all.map { $0.abbreviation }
    }
}
