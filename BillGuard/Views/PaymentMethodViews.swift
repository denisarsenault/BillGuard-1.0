//
//  PaymentMethodViews.swift
//  BillGuard
//
//  Payment method management views
//

import SwiftUI

// MARK: - Payment Method List View

struct PaymentMethodListView: View {
    @EnvironmentObject var patientDataService: PatientDataService
    
    let patientId: String
    
    @State private var showingAddMethod = false
    @State private var selectedMethod: PaymentMethod?
    
    private var methods: [PaymentMethod] {
        patientDataService.paymentMethods(for: patientId)
            .sorted { ($0.isDefault ? 0 : 1) < ($1.isDefault ? 0 : 1) }
    }
    
    private var cardMethods: [PaymentMethod] {
        methods.filter { $0.isCard }
    }
    
    private var digitalMethods: [PaymentMethod] {
        methods.filter { $0.isDigitalWallet }
    }
    
    private var otherMethods: [PaymentMethod] {
        methods.filter { !$0.isCard && !$0.isDigitalWallet }
    }
    
    var body: some View {
        Group {
            if methods.isEmpty {
                emptyState
            } else {
                methodList
            }
        }
        .navigationTitle("Payment Methods").brandToolbar(title: "Payments", showPatient: true)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddMethod = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddMethod) {
            AddPaymentMethodView(patientId: patientId)
                .environmentObject(patientDataService)
        }
        .sheet(item: $selectedMethod) { method in
            PaymentMethodDetailView(method: method)
                .environmentObject(patientDataService)
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "creditcard")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("No Payment Methods")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Add payment methods to track how you pay for medical bills.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Button {
                showingAddMethod = true
            } label: {
                Label("Add Payment Method", systemImage: "plus.circle.fill")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 10)
        }
    }
    
    private var methodList: some View {
        List {
            if !cardMethods.isEmpty {
                Section(header: Text("Cards")) {
                    ForEach(cardMethods) { method in
                        PaymentMethodRow(method: method)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedMethod = method
                            }
                    }
                    .onDelete { offsets in
                        deleteMethods(at: offsets, from: cardMethods)
                    }
                }
            }
            
            if !digitalMethods.isEmpty {
                Section(header: Text("Digital Wallets")) {
                    ForEach(digitalMethods) { method in
                        PaymentMethodRow(method: method)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedMethod = method
                            }
                    }
                    .onDelete { offsets in
                        deleteMethods(at: offsets, from: digitalMethods)
                    }
                }
            }
            
            if !otherMethods.isEmpty {
                Section(header: Text("Other")) {
                    ForEach(otherMethods) { method in
                        PaymentMethodRow(method: method)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedMethod = method
                            }
                    }
                    .onDelete { offsets in
                        deleteMethods(at: offsets, from: otherMethods)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }
    
    private func deleteMethods(at offsets: IndexSet, from list: [PaymentMethod]) {
        for index in offsets {
            patientDataService.deletePaymentMethod(list[index])
        }
    }
}

// MARK: - Payment Method Row

struct PaymentMethodRow: View {
    let method: PaymentMethod
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: method.type.icon)
                .font(.title2)
                .foregroundColor(method.isExpired ? .red : .blue)
                .frame(width: 40, height: 40)
                .background(
                    Circle()
                        .fill((method.isExpired ? Color.red : Color("BrandCyan")).opacity(0.1))
                )
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(method.displayName)
                        .font(.headline)
                    
                    if method.isDefault {
                        Text("DEFAULT")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.green.opacity(0.15)))
                            .foregroundColor(.green)
                    }
                }
                
                if let expiry = method.expirationDisplay {
                    HStack(spacing: 4) {
                        Text("Exp: \(expiry)")
                            .font(.caption)
                            .foregroundColor(method.isExpired ? .red : .secondary)
                        
                        if method.isExpired {
                            Text("EXPIRED")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.red)
                        }
                    }
                }
                
                if let handle = method.digitalPaymentHandle {
                    Text(handle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Payment Method Detail View

struct PaymentMethodDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var patientDataService: PatientDataService
    
    let method: PaymentMethod
    
    var body: some View {
        NavigationStack {
            List {
                // Card Visual
                if method.isCard {
                    Section {
                        cardVisual
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
                
                // Basic Info
                Section(header: Text("Details")) {
                    row("Type", method.type.rawValue)
                    
                    if let nickname = method.nickname {
                        row("Nickname", nickname)
                    }
                    
                    if let brand = method.cardBrand {
                        row("Card Brand", brand.rawValue)
                    }
                    
                    if let masked = method.maskedNumber {
                        row("Card Number", masked)
                    }
                    
                    if let expiry = method.expirationDisplay {
                        HStack {
                            Text("Expiration")
                            Spacer()
                            Text(expiry)
                                .foregroundColor(method.isExpired ? .red : .secondary)
                            if method.isExpired {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.red)
                                    .font(.caption)
                            }
                        }
                    }
                    
                    if let cardholder = method.cardholderName {
                        row("Cardholder", cardholder)
                    }
                    
                    row("Default", method.isDefault ? "Yes" : "No")
                }
                
                // Bank Info
                if method.type == .bankAccount {
                    Section(header: Text("Bank Account")) {
                        if let bank = method.bankName {
                            row("Bank", bank)
                        }
                        if let last4 = method.accountLastFour {
                            row("Account", "•••• \(last4)")
                        }
                        if let type = method.accountType {
                            row("Account Type", type.rawValue)
                        }
                    }
                }
                
                // Digital Payment
                if method.isDigitalWallet {
                    Section(header: Text("Account Info")) {
                        if let handle = method.digitalPaymentHandle {
                            row("Handle/Email", handle)
                        }
                    }
                }
                
                // Billing Address
                if let address = method.billingAddress {
                    Section(header: Text("Billing Address")) {
                        VStack(alignment: .leading, spacing: 4) {
                            if !address.street1.isEmpty {
                                Text(address.street1)
                            }
                            if let street2 = address.street2, !street2.isEmpty {
                                Text(street2)
                            }
                            HStack(spacing: 0) {
                                Text(address.city)
                                if !address.state.isEmpty {
                                    Text(", \(address.state) ")
                                }
                                Text(address.zipCode)
                            }
                        }
                        .foregroundColor(.secondary)
                    }
                }
                
                // Notes
                if let notes = method.notes, !notes.isEmpty {
                    Section(header: Text("Notes")) {
                        Text(notes)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(method.type.rawValue)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
    
    private var cardVisual: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    LinearGradient(
                        colors: method.type == .hsa || method.type == .fsa
                            ? [.green, .teal]
                            : [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(height: 200)
            
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(method.type.rawValue)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                    Spacer()
                    if let brand = method.cardBrand {
                        Text(brand.rawValue)
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                }
                
                Spacer()
                
                Text(method.maskedNumber ?? "•••• •••• •••• ••••")
                    .font(.title2)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .tracking(2)
                
                HStack {
                    VStack(alignment: .leading) {
                        Text("CARDHOLDER")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.6))
                        Text(method.cardholderName ?? "Name")
                            .font(.subheadline)
                            .foregroundColor(.white)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing) {
                        Text("EXPIRES")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.6))
                        Text(method.expirationDisplay ?? "MM/YY")
                            .font(.subheadline)
                            .foregroundColor(.white)
                    }
                }
                
                if method.isDefault {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Default Payment Method")
                    }
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
                }
            }
            .padding(24)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
    
    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Add Payment Method View

struct AddPaymentMethodView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var patientDataService: PatientDataService
    
    let patientId: String
    
    @State private var type: PaymentMethodType = .creditCard
    @State private var nickname = ""
    @State private var isDefault = false
    
    // Card
    @State private var cardBrand: CardBrand = .visa
    @State private var lastFour = ""
    @State private var expirationMonth = ""
    @State private var expirationYear = ""
    @State private var cardholderName = ""
    
    // Bank
    @State private var bankName = ""
    @State private var accountLastFour = ""
    @State private var accountType: BankAccountType = .checking
    
    // Digital
    @State private var digitalHandle = ""
    
    @State private var notes = ""
    
    private var isCardType: Bool {
        [.creditCard, .debitCard, .hsa, .fsa].contains(type)
    }
    
    private var isDigitalType: Bool {
        [.venmo, .paypal, .zelle, .cashApp].contains(type)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                // Type
                Section(header: Text("Payment Type")) {
                    Picker("Type", selection: $type) {
                        ForEach(PaymentMethodType.allCases, id: \.self) { t in
                            Label(t.rawValue, systemImage: t.icon).tag(t)
                        }
                    }
                    
                    TextField("Nickname (optional)", text: $nickname)
                    Toggle("Default Payment Method", isOn: $isDefault)
                }
                
                // Card details
                if isCardType {
                    Section(header: Text("Card Details")) {
                        Picker("Card Brand", selection: $cardBrand) {
                            ForEach(CardBrand.allCases, id: \.self) { brand in
                                Text(brand.rawValue).tag(brand)
                            }
                        }
                        
                        TextField("Last 4 Digits", text: $lastFour)
                            .keyboardType(.numberPad)
                            .onChange(of: lastFour) { _, new in
                                if new.count > 4 {
                                    lastFour = String(new.prefix(4))
                                }
                            }
                        
                        HStack {
                            TextField("MM", text: $expirationMonth)
                                .keyboardType(.numberPad)
                                .frame(width: 50)
                                .onChange(of: expirationMonth) { _, new in
                                    if new.count > 2 { expirationMonth = String(new.prefix(2)) }
                                }
                            Text("/")
                                .foregroundColor(.secondary)
                            TextField("YYYY", text: $expirationYear)
                                .keyboardType(.numberPad)
                                .frame(width: 60)
                                .onChange(of: expirationYear) { _, new in
                                    if new.count > 4 { expirationYear = String(new.prefix(4)) }
                                }
                        }
                        
                        TextField("Cardholder Name", text: $cardholderName)
                    }
                }
                
                // Bank details
                if type == .bankAccount {
                    Section(header: Text("Bank Account Details")) {
                        TextField("Bank Name", text: $bankName)
                        TextField("Last 4 Digits of Account", text: $accountLastFour)
                            .keyboardType(.numberPad)
                            .onChange(of: accountLastFour) { _, new in
                                if new.count > 4 { accountLastFour = String(new.prefix(4)) }
                            }
                        Picker("Account Type", selection: $accountType) {
                            ForEach(BankAccountType.allCases, id: \.self) { t in
                                Text(t.rawValue).tag(t)
                            }
                        }
                    }
                }
                
                // Digital wallet
                if isDigitalType {
                    Section(header: Text("Account Info")) {
                        TextField("Username / Email / Phone", text: $digitalHandle)
                    }
                }
                
                // Notes
                Section(header: Text("Notes")) {
                    TextEditor(text: $notes)
                        .frame(minHeight: 60)
                }
            }
            .navigationTitle("Add Payment Method")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveMethod()
                    }
                }
            }
        }
    }
    
    private func saveMethod() {
        let method = PaymentMethod(
            patientId: patientId,
            type: type,
            nickname: nickname.isEmpty ? nil : nickname,
            isDefault: isDefault,
            cardBrand: isCardType ? cardBrand : nil,
            lastFourDigits: lastFour.isEmpty ? nil : lastFour,
            expirationMonth: Int(expirationMonth),
            expirationYear: Int(expirationYear),
            cardholderName: cardholderName.isEmpty ? nil : cardholderName,
            bankName: bankName.isEmpty ? nil : bankName,
            accountLastFour: accountLastFour.isEmpty ? nil : accountLastFour,
            accountType: type == .bankAccount ? accountType : nil,
            digitalPaymentHandle: digitalHandle.isEmpty ? nil : digitalHandle,
            notes: notes.isEmpty ? nil : notes
        )
        
        // If setting as default, unset other defaults
        if isDefault {
            for var existing in patientDataService.paymentMethods(for: patientId) {
                if existing.isDefault {
                    existing.isDefault = false
                    patientDataService.savePaymentMethod(existing)
                }
            }
        }
        
        patientDataService.savePaymentMethod(method)
        dismiss()
    }
}
