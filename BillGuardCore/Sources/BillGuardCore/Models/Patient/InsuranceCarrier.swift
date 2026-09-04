//
//  InsuranceCarrier.swift
//  BillGuard
//
//  Insurance carrier/company model
//

import Foundation
import CloudKit

// MARK: - Insurance Carrier Model

public struct InsuranceCarrier: Identifiable, Codable, Hashable {
    public var id: String
    public var name: String
    public var shortName: String?
    
    // Contact Information
    public var address: Address?
    public var phones: [PhoneNumber]
    public var fax: String?
    public var website: String?
    public var memberPortalUrl: String?
    public var providerPortalUrl: String?
    
    // Claims Information
    public var claimsAddress: Address?
    public var claimsPhone: String?
    public var claimsFax: String?
    public var claimsEmail: String?
    public var electronicPayerId: String?  // EDI Payer ID
    
    // Customer Service
    public var customerServicePhone: String?
    public var customerServiceHours: String?
    
    // Pharmacy Benefits
    public var pharmacyBenefitsPhone: String?
    public var pharmacyBenefitsManager: String?  // PBM name
    
    // Notes
    public var notes: String?
    
    // Logo (URL or asset name)
    public var logoUrl: String?
    
    // Metadata
    public var createdAt: Date
    public var updatedAt: Date
    public var recordId: String?
    
    public init(
        id: String = UUID().uuidString,
        name: String,
        shortName: String? = nil,
        address: Address? = nil,
        phones: [PhoneNumber] = [],
        fax: String? = nil,
        website: String? = nil,
        memberPortalUrl: String? = nil,
        providerPortalUrl: String? = nil,
        claimsAddress: Address? = nil,
        claimsPhone: String? = nil,
        claimsFax: String? = nil,
        claimsEmail: String? = nil,
        electronicPayerId: String? = nil,
        customerServicePhone: String? = nil,
        customerServiceHours: String? = nil,
        pharmacyBenefitsPhone: String? = nil,
        pharmacyBenefitsManager: String? = nil,
        notes: String? = nil,
        logoUrl: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        recordId: String? = nil
    ) {
        self.id = id
        self.name = name
        self.shortName = shortName
        self.address = address
        self.phones = phones
        self.fax = fax
        self.website = website
        self.memberPortalUrl = memberPortalUrl
        self.providerPortalUrl = providerPortalUrl
        self.claimsAddress = claimsAddress
        self.claimsPhone = claimsPhone
        self.claimsFax = claimsFax
        self.claimsEmail = claimsEmail
        self.electronicPayerId = electronicPayerId
        self.customerServicePhone = customerServicePhone
        self.customerServiceHours = customerServiceHours
        self.pharmacyBenefitsPhone = pharmacyBenefitsPhone
        self.pharmacyBenefitsManager = pharmacyBenefitsManager
        self.notes = notes
        self.logoUrl = logoUrl
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.recordId = recordId
    }
    
    // MARK: - Computed Properties
    
    public var displayName: String {
        shortName ?? name
    }
    
    public var primaryPhone: String? {
        customerServicePhone ?? phones.first?.number
    }
}

// MARK: - CloudKit Support

extension InsuranceCarrier {
    static let recordType = "InsuranceCarrier"
    
    init?(from record: CKRecord) {
        guard record.recordType == InsuranceCarrier.recordType,
              let name = record["name"] as? String else {
            return nil
        }
        
        self.id = record["id"] as? String ?? record.recordID.recordName
        self.name = name
        self.shortName = record["shortName"] as? String
        
        if let addressData = record["address"] as? Data {
            self.address = try? JSONDecoder().decode(Address.self, from: addressData)
        }
        
        if let phonesData = record["phones"] as? Data {
            self.phones = (try? JSONDecoder().decode([PhoneNumber].self, from: phonesData)) ?? []
        } else {
            self.phones = []
        }
        
        self.fax = record["fax"] as? String
        self.website = record["website"] as? String
        self.memberPortalUrl = record["memberPortalUrl"] as? String
        self.providerPortalUrl = record["providerPortalUrl"] as? String
        
        if let claimsAddressData = record["claimsAddress"] as? Data {
            self.claimsAddress = try? JSONDecoder().decode(Address.self, from: claimsAddressData)
        }
        
        self.claimsPhone = record["claimsPhone"] as? String
        self.claimsFax = record["claimsFax"] as? String
        self.claimsEmail = record["claimsEmail"] as? String
        self.electronicPayerId = record["electronicPayerId"] as? String
        self.customerServicePhone = record["customerServicePhone"] as? String
        self.customerServiceHours = record["customerServiceHours"] as? String
        self.pharmacyBenefitsPhone = record["pharmacyBenefitsPhone"] as? String
        self.pharmacyBenefitsManager = record["pharmacyBenefitsManager"] as? String
        self.notes = record["notes"] as? String
        self.logoUrl = record["logoUrl"] as? String
        self.createdAt = record["createdAt"] as? Date ?? record.creationDate ?? Date()
        self.updatedAt = record["updatedAt"] as? Date ?? record.modificationDate ?? Date()
        self.recordId = record.recordID.recordName
    }
    
    func toRecord(existingRecord: CKRecord? = nil) -> CKRecord {
        let record = existingRecord ?? CKRecord(recordType: InsuranceCarrier.recordType)
        
        record["id"] = id
        record["name"] = name
        record["shortName"] = shortName
        
        if let address = address, let data = try? JSONEncoder().encode(address) {
            record["address"] = data
        }
        
        if let data = try? JSONEncoder().encode(phones) {
            record["phones"] = data
        }
        
        record["fax"] = fax
        record["website"] = website
        record["memberPortalUrl"] = memberPortalUrl
        record["providerPortalUrl"] = providerPortalUrl
        
        if let claimsAddress = claimsAddress, let data = try? JSONEncoder().encode(claimsAddress) {
            record["claimsAddress"] = data
        }
        
        record["claimsPhone"] = claimsPhone
        record["claimsFax"] = claimsFax
        record["claimsEmail"] = claimsEmail
        record["electronicPayerId"] = electronicPayerId
        record["customerServicePhone"] = customerServicePhone
        record["customerServiceHours"] = customerServiceHours
        record["pharmacyBenefitsPhone"] = pharmacyBenefitsPhone
        record["pharmacyBenefitsManager"] = pharmacyBenefitsManager
        record["notes"] = notes
        record["logoUrl"] = logoUrl
        record["createdAt"] = createdAt
        record["updatedAt"] = Date()
        
        return record
    }
}

// MARK: - Common Carriers (Pre-populated list)

extension InsuranceCarrier {
    static let commonCarriers: [InsuranceCarrier] = [
        InsuranceCarrier(name: "Aetna", shortName: "Aetna", customerServicePhone: "1-800-872-3862"),
        InsuranceCarrier(name: "Anthem Blue Cross Blue Shield", shortName: "Anthem", customerServicePhone: "1-800-331-1476"),
        InsuranceCarrier(name: "Blue Cross Blue Shield", shortName: "BCBS", customerServicePhone: "1-800-262-2583"),
        InsuranceCarrier(name: "Cigna", shortName: "Cigna", customerServicePhone: "1-800-997-1654"),
        InsuranceCarrier(name: "Humana", shortName: "Humana", customerServicePhone: "1-800-457-4708"),
        InsuranceCarrier(name: "Kaiser Permanente", shortName: "Kaiser", customerServicePhone: "1-800-464-4000"),
        InsuranceCarrier(name: "Medicare", shortName: "Medicare", customerServicePhone: "1-800-633-4227"),
        InsuranceCarrier(name: "Medicaid", shortName: "Medicaid"),
        InsuranceCarrier(name: "Molina Healthcare", shortName: "Molina", customerServicePhone: "1-888-562-5442"),
        InsuranceCarrier(name: "Oscar Health", shortName: "Oscar", customerServicePhone: "1-855-672-2788"),
        InsuranceCarrier(name: "UnitedHealthcare", shortName: "UHC", customerServicePhone: "1-800-328-5979"),
        InsuranceCarrier(name: "TRICARE", shortName: "TRICARE", customerServicePhone: "1-800-874-2273"),
    ]
}
