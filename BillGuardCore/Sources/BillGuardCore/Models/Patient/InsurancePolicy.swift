//
//  InsurancePolicy.swift
//  BillGuard
//
//  Patient's specific insurance policy with a carrier
//

import Foundation
import CloudKit

// MARK: - Policy Type

public enum PolicyType: String, Codable, CaseIterable {
    case medical = "Medical"
    case dental = "Dental"
    case vision = "Vision"
    case prescription = "Prescription"
    case supplemental = "Supplemental"
    case medicare = "Medicare"
    case medicaid = "Medicaid"
    case tricare = "TRICARE"
    case workersComp = "Workers Comp"
    case auto = "Auto (Medical)"
    case other = "Other"
}

// MARK: - Plan Type

public enum PlanType: String, Codable, CaseIterable {
    case hmo = "HMO"
    case ppo = "PPO"
    case epo = "EPO"
    case pos = "POS"
    case hdhp = "HDHP"
    case medicareAdvantage = "Medicare Advantage"
    case medicareSupplement = "Medicare Supplement"
    case medicarePartD = "Medicare Part D"
    case medicaid = "Medicaid"
    case tricare = "TRICARE"
    case other = "Other"
}

// MARK: - Coverage Level

public enum CoverageLevel: String, Codable, CaseIterable {
    case individual = "Individual"
    case individualPlusSpouse = "Individual + Spouse"
    case individualPlusChild = "Individual + Child"
    case individualPlusChildren = "Individual + Children"
    case family = "Family"
}

// MARK: - Insurance Policy Model

public struct InsurancePolicy: Identifiable, Codable, Hashable {
    public var id: String
    public var patientId: String
    public var carrierId: String
    
    // Policy Information
    public var policyType: PolicyType
    public var planType: PlanType?
    public var planName: String?
    public var coverageLevel: CoverageLevel?
    
    // Member Information
    public var memberId: String
    public var groupNumber: String?
    public var policyNumber: String?
    public var rxBin: String?           // Pharmacy BIN number
    public var rxPcn: String?           // Pharmacy PCN
    public var rxGroup: String?         // Pharmacy Group
    
    // Subscriber Information (if different from patient)
    public var subscriberName: String?
    public var subscriberDOB: Date?
    public var subscriberRelationship: PatientRelationship?
    public var subscriberEmployer: String?
    
    // Coverage Dates
    public var effectiveDate: Date?
    public var terminationDate: Date?
    
    // Cost Sharing
    public var copay: CopayStructure?
    public var deductible: DeductibleInfo?
    public var coinsurance: Double?       // Percentage (e.g., 0.20 for 20%)
    public var outOfPocketMax: Double?
    public var outOfPocketMet: Double?
    
    // Priority
    public var isPrimary: Bool
    public var coordinationOfBenefits: Int?  // 1 = primary, 2 = secondary, etc.
    
    // Card Images
    public var frontCardImageUrl: String?
    public var backCardImageUrl: String?
    
    // Notes
    public var notes: String?
    
    // Metadata
    public var createdAt: Date
    public var updatedAt: Date
    public var recordId: String?
    
    public init(
        id: String = UUID().uuidString,
        patientId: String,
        carrierId: String,
        policyType: PolicyType = .medical,
        planType: PlanType? = nil,
        planName: String? = nil,
        coverageLevel: CoverageLevel? = nil,
        memberId: String,
        groupNumber: String? = nil,
        policyNumber: String? = nil,
        rxBin: String? = nil,
        rxPcn: String? = nil,
        rxGroup: String? = nil,
        subscriberName: String? = nil,
        subscriberDOB: Date? = nil,
        subscriberRelationship: PatientRelationship? = nil,
        subscriberEmployer: String? = nil,
        effectiveDate: Date? = nil,
        terminationDate: Date? = nil,
        copay: CopayStructure? = nil,
        deductible: DeductibleInfo? = nil,
        coinsurance: Double? = nil,
        outOfPocketMax: Double? = nil,
        outOfPocketMet: Double? = nil,
        isPrimary: Bool = true,
        coordinationOfBenefits: Int? = nil,
        frontCardImageUrl: String? = nil,
        backCardImageUrl: String? = nil,
        notes: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        recordId: String? = nil
    ) {
        self.id = id
        self.patientId = patientId
        self.carrierId = carrierId
        self.policyType = policyType
        self.planType = planType
        self.planName = planName
        self.coverageLevel = coverageLevel
        self.memberId = memberId
        self.groupNumber = groupNumber
        self.policyNumber = policyNumber
        self.rxBin = rxBin
        self.rxPcn = rxPcn
        self.rxGroup = rxGroup
        self.subscriberName = subscriberName
        self.subscriberDOB = subscriberDOB
        self.subscriberRelationship = subscriberRelationship
        self.subscriberEmployer = subscriberEmployer
        self.effectiveDate = effectiveDate
        self.terminationDate = terminationDate
        self.copay = copay
        self.deductible = deductible
        self.coinsurance = coinsurance
        self.outOfPocketMax = outOfPocketMax
        self.outOfPocketMet = outOfPocketMet
        self.isPrimary = isPrimary
        self.coordinationOfBenefits = coordinationOfBenefits
        self.frontCardImageUrl = frontCardImageUrl
        self.backCardImageUrl = backCardImageUrl
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.recordId = recordId
    }
    
    // MARK: - Computed Properties
    
    public var isActive: Bool {
        let now = Date()
        if let termDate = terminationDate, termDate < now {
            return false
        }
        if let effDate = effectiveDate, effDate > now {
            return false
        }
        return true
    }
    
    public var remainingDeductible: Double? {
        guard let deductible = deductible else { return nil }
        return max(0, deductible.individual - deductible.individualMet)
    }
    
    public var remainingOutOfPocket: Double? {
        guard let max = outOfPocketMax, let met = outOfPocketMet else { return nil }
        return Swift.max(0, max - met)
    }
    
    public var displayMemberId: String {
        if let group = groupNumber {
            return "\(memberId) / \(group)"
        }
        return memberId
    }
}

// MARK: - Copay Structure

public struct CopayStructure: Codable, Hashable {
    public var primaryCare: Double?
    public var specialist: Double?
    public var urgentCare: Double?
    public var emergencyRoom: Double?
    public var genericDrug: Double?
    public var brandDrug: Double?
    public var specialtyDrug: Double?
    public var preventiveCare: Double?
    public var labWork: Double?
    public var imaging: Double?
    public var mentalHealth: Double?
    public var physicalTherapy: Double?
    
    public init(
        primaryCare: Double? = nil,
        specialist: Double? = nil,
        urgentCare: Double? = nil,
        emergencyRoom: Double? = nil,
        genericDrug: Double? = nil,
        brandDrug: Double? = nil,
        specialtyDrug: Double? = nil,
        preventiveCare: Double? = nil,
        labWork: Double? = nil,
        imaging: Double? = nil,
        mentalHealth: Double? = nil,
        physicalTherapy: Double? = nil
    ) {
        self.primaryCare = primaryCare
        self.specialist = specialist
        self.urgentCare = urgentCare
        self.emergencyRoom = emergencyRoom
        self.genericDrug = genericDrug
        self.brandDrug = brandDrug
        self.specialtyDrug = specialtyDrug
        self.preventiveCare = preventiveCare
        self.labWork = labWork
        self.imaging = imaging
        self.mentalHealth = mentalHealth
        self.physicalTherapy = physicalTherapy
    }
}

// MARK: - Deductible Info

public struct DeductibleInfo: Codable, Hashable {
    public var individual: Double
    public var individualMet: Double
    public var family: Double?
    public var familyMet: Double?
    
    public init(individual: Double, individualMet: Double = 0, family: Double? = nil, familyMet: Double? = nil) {
        self.individual = individual
        self.individualMet = individualMet
        self.family = family
        self.familyMet = familyMet
    }
    
    public var individualRemaining: Double {
        max(0, individual - individualMet)
    }
    
    public var familyRemaining: Double? {
        guard let fam = family, let met = familyMet else { return nil }
        return max(0, fam - met)
    }
    
    public var individualPercentMet: Double {
        guard individual > 0 else { return 0 }
        return min(1.0, individualMet / individual)
    }
}

// MARK: - CloudKit Support

extension InsurancePolicy {
    static let recordType = "InsurancePolicy"
    
    init?(from record: CKRecord) {
        guard record.recordType == InsurancePolicy.recordType,
              let patientId = record["patientId"] as? String,
              let carrierId = record["carrierId"] as? String,
              let memberId = record["memberId"] as? String,
              let policyTypeRaw = record["policyType"] as? String,
              let policyType = PolicyType(rawValue: policyTypeRaw) else {
            return nil
        }
        
        self.id = record["id"] as? String ?? record.recordID.recordName
        self.patientId = patientId
        self.carrierId = carrierId
        self.policyType = policyType
        self.memberId = memberId
        
        if let planTypeRaw = record["planType"] as? String {
            self.planType = PlanType(rawValue: planTypeRaw)
        }
        
        self.planName = record["planName"] as? String
        
        if let coverageLevelRaw = record["coverageLevel"] as? String {
            self.coverageLevel = CoverageLevel(rawValue: coverageLevelRaw)
        }
        
        self.groupNumber = record["groupNumber"] as? String
        self.policyNumber = record["policyNumber"] as? String
        self.rxBin = record["rxBin"] as? String
        self.rxPcn = record["rxPcn"] as? String
        self.rxGroup = record["rxGroup"] as? String
        
        self.subscriberName = record["subscriberName"] as? String
        self.subscriberDOB = record["subscriberDOB"] as? Date
        if let subRelRaw = record["subscriberRelationship"] as? String {
            self.subscriberRelationship = PatientRelationship(rawValue: subRelRaw)
        }
        self.subscriberEmployer = record["subscriberEmployer"] as? String
        
        self.effectiveDate = record["effectiveDate"] as? Date
        self.terminationDate = record["terminationDate"] as? Date
        
        if let copayData = record["copay"] as? Data {
            self.copay = try? JSONDecoder().decode(CopayStructure.self, from: copayData)
        }
        
        if let deductibleData = record["deductible"] as? Data {
            self.deductible = try? JSONDecoder().decode(DeductibleInfo.self, from: deductibleData)
        }
        
        self.coinsurance = record["coinsurance"] as? Double
        self.outOfPocketMax = record["outOfPocketMax"] as? Double
        self.outOfPocketMet = record["outOfPocketMet"] as? Double
        
        self.isPrimary = record["isPrimary"] as? Bool ?? true
        self.coordinationOfBenefits = record["coordinationOfBenefits"] as? Int
        
        self.frontCardImageUrl = record["frontCardImageUrl"] as? String
        self.backCardImageUrl = record["backCardImageUrl"] as? String
        
        self.notes = record["notes"] as? String
        self.createdAt = record["createdAt"] as? Date ?? record.creationDate ?? Date()
        self.updatedAt = record["updatedAt"] as? Date ?? record.modificationDate ?? Date()
        self.recordId = record.recordID.recordName
    }
    
    func toRecord(existingRecord: CKRecord? = nil) -> CKRecord {
        let record = existingRecord ?? CKRecord(recordType: InsurancePolicy.recordType)
        
        record["id"] = id
        record["patientId"] = patientId
        record["carrierId"] = carrierId
        record["policyType"] = policyType.rawValue
        record["planType"] = planType?.rawValue
        record["planName"] = planName
        record["coverageLevel"] = coverageLevel?.rawValue
        record["memberId"] = memberId
        record["groupNumber"] = groupNumber
        record["policyNumber"] = policyNumber
        record["rxBin"] = rxBin
        record["rxPcn"] = rxPcn
        record["rxGroup"] = rxGroup
        record["subscriberName"] = subscriberName
        record["subscriberDOB"] = subscriberDOB
        record["subscriberRelationship"] = subscriberRelationship?.rawValue
        record["subscriberEmployer"] = subscriberEmployer
        record["effectiveDate"] = effectiveDate
        record["terminationDate"] = terminationDate
        
        if let copay = copay, let data = try? JSONEncoder().encode(copay) {
            record["copay"] = data
        }
        
        if let deductible = deductible, let data = try? JSONEncoder().encode(deductible) {
            record["deductible"] = data
        }
        
        record["coinsurance"] = coinsurance
        record["outOfPocketMax"] = outOfPocketMax
        record["outOfPocketMet"] = outOfPocketMet
        record["isPrimary"] = isPrimary
        record["coordinationOfBenefits"] = coordinationOfBenefits
        record["frontCardImageUrl"] = frontCardImageUrl
        record["backCardImageUrl"] = backCardImageUrl
        record["notes"] = notes
        record["createdAt"] = createdAt
        record["updatedAt"] = Date()
        
        return record
    }
}
