//
//  PaymentMethod.swift
//  BillGuard
//
//  Payment method model (credit cards, debit cards, cash apps)
//

import Foundation
import CloudKit

// MARK: - Payment Method Type

enum PaymentMethodType: String, Codable, CaseIterable {
    case creditCard = "Credit Card"
    case debitCard = "Debit Card"
    case hsa = "HSA Card"
    case fsa = "FSA Card"
    case bankAccount = "Bank Account"
    case venmo = "Venmo"
    case paypal = "PayPal"
    case applePay = "Apple Pay"
    case googlePay = "Google Pay"
    case zelle = "Zelle"
    case cashApp = "Cash App"
    case check = "Check"
    case cash = "Cash"
    case other = "Other"
    
    var icon: String {
        switch self {
        case .creditCard: return "creditcard.fill"
        case .debitCard: return "creditcard"
        case .hsa, .fsa: return "cross.case.fill"
        case .bankAccount: return "building.columns.fill"
        case .venmo: return "v.circle.fill"
        case .paypal: return "p.circle.fill"
        case .applePay: return "apple.logo"
        case .googlePay: return "g.circle.fill"
        case .zelle: return "z.circle.fill"
        case .cashApp: return "dollarsign.square.fill"
        case .check: return "doc.text.fill"
        case .cash: return "banknote.fill"
        case .other: return "creditcard.trianglebadge.exclamationmark"
        }
    }
}

// MARK: - Card Brand

enum CardBrand: String, Codable, CaseIterable {
    case visa = "Visa"
    case mastercard = "Mastercard"
    case amex = "American Express"
    case discover = "Discover"
    case other = "Other"
    
    var icon: String {
        switch self {
        case .visa: return "v.square.fill"
        case .mastercard: return "m.square.fill"
        case .amex: return "a.square.fill"
        case .discover: return "d.square.fill"
        case .other: return "creditcard.fill"
        }
    }
}

// MARK: - Payment Method Model

struct PaymentMethod: Identifiable, Codable, Hashable {
    var id: String
    var patientId: String
    
    var type: PaymentMethodType
    var nickname: String?
    var isDefault: Bool
    
    // Card Information (for cards)
    var cardBrand: CardBrand?
    var lastFourDigits: String?
    var expirationMonth: Int?
    var expirationYear: Int?
    var cardholderName: String?
    
    // Bank Account Information
    var bankName: String?
    var accountLastFour: String?
    var routingLastFour: String?
    var accountType: BankAccountType?
    
    // Digital Payment Info
    var digitalPaymentHandle: String?  // Username/email/phone for Venmo, PayPal, etc.
    
    // Billing Address
    var billingAddress: Address?
    
    // Notes
    var notes: String?
    
    // Metadata
    var createdAt: Date
    var updatedAt: Date
    var recordId: String?
    
    init(
        id: String = UUID().uuidString,
        patientId: String,
        type: PaymentMethodType,
        nickname: String? = nil,
        isDefault: Bool = false,
        cardBrand: CardBrand? = nil,
        lastFourDigits: String? = nil,
        expirationMonth: Int? = nil,
        expirationYear: Int? = nil,
        cardholderName: String? = nil,
        bankName: String? = nil,
        accountLastFour: String? = nil,
        routingLastFour: String? = nil,
        accountType: BankAccountType? = nil,
        digitalPaymentHandle: String? = nil,
        billingAddress: Address? = nil,
        notes: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        recordId: String? = nil
    ) {
        self.id = id
        self.patientId = patientId
        self.type = type
        self.nickname = nickname
        self.isDefault = isDefault
        self.cardBrand = cardBrand
        self.lastFourDigits = lastFourDigits
        self.expirationMonth = expirationMonth
        self.expirationYear = expirationYear
        self.cardholderName = cardholderName
        self.bankName = bankName
        self.accountLastFour = accountLastFour
        self.routingLastFour = routingLastFour
        self.accountType = accountType
        self.digitalPaymentHandle = digitalPaymentHandle
        self.billingAddress = billingAddress
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.recordId = recordId
    }
    
    // MARK: - Computed Properties
    
    var displayName: String {
        if let nickname = nickname {
            return nickname
        }
        
        switch type {
        case .creditCard, .debitCard, .hsa, .fsa:
            if let brand = cardBrand, let last4 = lastFourDigits {
                return "\(brand.rawValue) •••• \(last4)"
            } else if let last4 = lastFourDigits {
                return "\(type.rawValue) •••• \(last4)"
            }
            return type.rawValue
            
        case .bankAccount:
            if let bank = bankName, let last4 = accountLastFour {
                return "\(bank) •••• \(last4)"
            }
            return type.rawValue
            
        case .venmo, .paypal, .zelle, .cashApp:
            if let handle = digitalPaymentHandle {
                return "\(type.rawValue): \(handle)"
            }
            return type.rawValue
            
        default:
            return type.rawValue
        }
    }
    
    var maskedNumber: String? {
        guard let last4 = lastFourDigits else { return nil }
        return "•••• •••• •••• \(last4)"
    }
    
    var expirationDisplay: String? {
        guard let month = expirationMonth, let year = expirationYear else { return nil }
        return String(format: "%02d/%02d", month, year % 100)
    }
    
    var isExpired: Bool {
        guard let month = expirationMonth, let year = expirationYear else { return false }
        let calendar = Calendar.current
        let now = Date()
        let currentYear = calendar.component(.year, from: now)
        let currentMonth = calendar.component(.month, from: now)
        
        if year < currentYear {
            return true
        } else if year == currentYear && month < currentMonth {
            return true
        }
        return false
    }
    
    var isCard: Bool {
        [.creditCard, .debitCard, .hsa, .fsa].contains(type)
    }
    
    var isDigitalWallet: Bool {
        [.venmo, .paypal, .applePay, .googlePay, .zelle, .cashApp].contains(type)
    }
}

// MARK: - Bank Account Type

enum BankAccountType: String, Codable, CaseIterable {
    case checking = "Checking"
    case savings = "Savings"
}

// MARK: - CloudKit Support

extension PaymentMethod {
    static let recordType = "PaymentMethod"
    
    init?(from record: CKRecord) {
        guard record.recordType == PaymentMethod.recordType,
              let patientId = record["patientId"] as? String,
              let typeRaw = record["type"] as? String,
              let type = PaymentMethodType(rawValue: typeRaw) else {
            return nil
        }
        
        self.id = record["id"] as? String ?? record.recordID.recordName
        self.patientId = patientId
        self.type = type
        self.nickname = record["nickname"] as? String
        self.isDefault = record["isDefault"] as? Bool ?? false
        
        if let brandRaw = record["cardBrand"] as? String {
            self.cardBrand = CardBrand(rawValue: brandRaw)
        }
        
        self.lastFourDigits = record["lastFourDigits"] as? String
        self.expirationMonth = record["expirationMonth"] as? Int
        self.expirationYear = record["expirationYear"] as? Int
        self.cardholderName = record["cardholderName"] as? String
        self.bankName = record["bankName"] as? String
        self.accountLastFour = record["accountLastFour"] as? String
        self.routingLastFour = record["routingLastFour"] as? String
        
        if let accountTypeRaw = record["accountType"] as? String {
            self.accountType = BankAccountType(rawValue: accountTypeRaw)
        }
        
        self.digitalPaymentHandle = record["digitalPaymentHandle"] as? String
        
        if let addressData = record["billingAddress"] as? Data {
            self.billingAddress = try? JSONDecoder().decode(Address.self, from: addressData)
        }
        
        self.notes = record["notes"] as? String
        self.createdAt = record["createdAt"] as? Date ?? record.creationDate ?? Date()
        self.updatedAt = record["updatedAt"] as? Date ?? record.modificationDate ?? Date()
        self.recordId = record.recordID.recordName
    }
    
    func toRecord(existingRecord: CKRecord? = nil) -> CKRecord {
        let record = existingRecord ?? CKRecord(recordType: PaymentMethod.recordType)
        
        record["id"] = id
        record["patientId"] = patientId
        record["type"] = type.rawValue
        record["nickname"] = nickname
        record["isDefault"] = isDefault
        record["cardBrand"] = cardBrand?.rawValue
        record["lastFourDigits"] = lastFourDigits
        record["expirationMonth"] = expirationMonth
        record["expirationYear"] = expirationYear
        record["cardholderName"] = cardholderName
        record["bankName"] = bankName
        record["accountLastFour"] = accountLastFour
        record["routingLastFour"] = routingLastFour
        record["accountType"] = accountType?.rawValue
        record["digitalPaymentHandle"] = digitalPaymentHandle
        
        if let billingAddress = billingAddress, let data = try? JSONEncoder().encode(billingAddress) {
            record["billingAddress"] = data
        }
        
        record["notes"] = notes
        record["createdAt"] = createdAt
        record["updatedAt"] = Date()
        
        return record
    }
}
