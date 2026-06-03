//
//  InfoView.swift
//  BillGuard
//
//  Information and help view
//

import SwiftUI

struct InfoView: View {
    
    @Environment(\.dismiss) private var dismiss
    @State private var showingCodeTypesInfo = false
    @State private var showingPricingInfo = false
    @State private var showingFAQ = false
    
    var body: some View {
        NavigationStack {
            List {
                // About Section
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "cross.case.fill")
                                .font(.largeTitle)
                                .foregroundColor(.accentColor)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("BillGuard")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                
                                Text("Medical Code Lookup")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Text("Understanding your medical bills shouldn't be complicated. BillGuard translates medical codes into plain English so you know exactly what you're being charged for.")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .lineSpacing(4)
                    }
                    .padding(.vertical, 8)
                }
                
                // Learn Section
                Section("Learn") {
                    NavigationLink {
                        CodeTypesInfoView()
                    } label: {
                        Label("Understanding Code Types", systemImage: "doc.text")
                    }
                    
                    NavigationLink {
                        PricingInfoView()
                    } label: {
                        Label("About Pricing Data", systemImage: "dollarsign.circle")
                    }
                    
                    NavigationLink {
                        FAQView()
                    } label: {
                        Label("FAQ", systemImage: "questionmark.circle")
                    }
                }
                
                // Tips Section
                Section("Tips") {
                    TipRow(
                        icon: "magnifyingglass",
                        title: "Search Smarter",
                        description: "Search by code number (99213) or description (knee MRI)"
                    )
                    
                    TipRow(
                        icon: "star",
                        title: "Save Codes",
                        description: "Tap the star to save codes for easy access later"
                    )
                    
                    TipRow(
                        icon: "square.and.arrow.up",
                        title: "Share with Others",
                        description: "Share code explanations with family or healthcare providers"
                    )
                }
                
                // Legal Section
                Section("Legal") {
                    NavigationLink {
                        DisclaimerView()
                    } label: {
                        Label("Disclaimer", systemImage: "exclamationmark.shield")
                    }
                    
                    NavigationLink {
                        PrivacyPolicyView()
                    } label: {
                        Label("Privacy Policy", systemImage: "hand.raised")
                    }
                    
                    NavigationLink {
                        TermsView()
                    } label: {
                        Label("Terms of Service", systemImage: "doc.text")
                    }
                }
                
                // App Info
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                } footer: {
                    Text("© 2024 BillGuard. All rights reserved.\nMedical code data provided for informational purposes only.")
                        .multilineTextAlignment(.center)
                        .padding(.top, 20)
                }
            }
            .navigationTitle("Information")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(Color("BrandCyan"))
                }
            }
        }
    }
}

// MARK: - Tip Row

struct TipRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.accentColor)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Code Types Info View

struct CodeTypesInfoView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // CPT
                CodeTypeCard(
                    type: "CPT",
                    fullName: "Current Procedural Terminology",
                    color: .blue,
                    description: "CPT codes describe medical procedures and services performed by healthcare providers. They're used to bill for things like office visits, surgeries, lab tests, and diagnostic imaging.",
                    examples: ["99213 – Office visit", "70450 – CT scan of head", "93000 – EKG test"]
                )
                
                // ICD-10
                CodeTypeCard(
                    type: "ICD-10",
                    fullName: "International Classification of Diseases",
                    color: .green,
                    description: "ICD-10 codes describe diagnoses and medical conditions. They tell insurance companies why you needed treatment. Every medical bill includes these codes to explain your condition.",
                    examples: ["J06.9 – Upper respiratory infection", "M54.5 – Low back pain", "E11.9 – Type 2 diabetes"]
                )
                
                // HCPCS
                CodeTypeCard(
                    type: "HCPCS",
                    fullName: "Healthcare Common Procedure Coding System",
                    color: .orange,
                    description: "HCPCS codes cover medical supplies, equipment, and services not included in CPT codes. They're commonly used for items like wheelchairs, ambulance services, and medications.",
                    examples: ["A4253 – Blood glucose test strips", "E0601 – CPAP machine", "J0129 – Abatacept injection"]
                )
            }
            .padding()
        }
        .navigationTitle("Code Types")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct CodeTypeCard: View {
    let type: String
    let fullName: String
    let color: Color
    let description: String
    let examples: [String]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(type)
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(color)
                    .cornerRadius(8)
                
                Text(fullName)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Text(description)
                .font(.body)
                .lineSpacing(4)
            
            VStack(alignment: .leading, spacing: 6) {
                Text("Examples:")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                ForEach(examples, id: \.self) { example in
                    Text("• \(example)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color("BrandNavy"))
        .cornerRadius(12)
    }
}

// MARK: - Pricing Info View

struct PricingInfoView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Where does pricing data come from?")
                    .font(.title3)
                    .fontWeight(.semibold)
                
                Text("The pricing information shown in BillGuard represents national averages compiled from multiple sources including Medicare reimbursement rates, hospital price transparency data, and healthcare cost databases.")
                    .lineSpacing(4)
                
                InfoBox(
                    icon: "exclamationmark.triangle",
                    title: "Important Note",
                    message: "Actual prices you pay may vary significantly based on your location, insurance plan, the specific provider, and whether you're treated in a hospital vs. outpatient facility.",
                    color: .orange
                )
                
                Text("Understanding the Price Range")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .padding(.top)
                
                VStack(alignment: .leading, spacing: 12) {
                    PriceExplanationRow(
                        label: "Low",
                        color: .green,
                        explanation: "Represents the lower end of typical costs, often seen at outpatient facilities or with strong insurance coverage."
                    )
                    
                    PriceExplanationRow(
                        label: "Average",
                        color: .blue,
                        explanation: "The median or typical cost most patients can expect to pay."
                    )
                    
                    PriceExplanationRow(
                        label: "High",
                        color: .orange,
                        explanation: "Higher end costs, often associated with hospital settings or out-of-network providers."
                    )
                }
                
                InfoBox(
                    icon: "lightbulb",
                    title: "Pro Tip",
                    message: "Always ask for an itemized bill and compare the codes with your explanation of benefits (EOB) from your insurance company.",
                    color: .blue
                )
            }
            .padding()
        }
        .navigationTitle("About Pricing")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct PriceExplanationRow: View {
    let label: String
    let color: Color
    let explanation: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(.headline)
                .foregroundColor(color)
                .frame(width: 70, alignment: .leading)
            
            Text(explanation)
                .font(.body)
                .foregroundColor(.secondary)
        }
    }
}

struct InfoBox: View {
    let icon: String
    let title: String
    let message: String
    let color: Color
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                
                Text(message)
                    .font(.body)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(color.opacity(0.1))
        .cornerRadius(12)
    }
}

// MARK: - FAQ View

struct FAQView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                FAQItem(
                    question: "What codes can I look up?",
                    answer: "BillGuard supports CPT (procedure codes), ICD-10 (diagnosis codes), and HCPCS (supply and service codes). These cover the vast majority of codes you'll see on medical bills."
                )
                
                FAQItem(
                    question: "Are the prices accurate?",
                    answer: "Prices shown are national averages and estimates. Your actual costs will depend on your insurance, location, and provider. Use them as a reference point, not a guarantee."
                )
                
                FAQItem(
                    question: "Can I dispute my bill using this app?",
                    answer: "BillGuard helps you understand your bill, but bill disputes should be handled directly with your provider or insurance company. The information here can help you identify potential errors or overcharges."
                )
                
                FAQItem(
                    question: "Do I need to create an account?",
                    answer: "No! BillGuard works without any account or login. Your saved codes are stored locally on your device for your privacy."
                )
                
                FAQItem(
                    question: "Is my search history private?",
                    answer: "Yes. All your searches and saved codes are stored only on your device. We don't track your medical searches or share any data."
                )
                
                FAQItem(
                    question: "How often is the data updated?",
                    answer: "We regularly update our code database to reflect the latest medical coding standards and pricing information."
                )
            }
            .padding()
        }
        .navigationTitle("FAQ")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct FAQItem: View {
    let question: String
    let answer: String
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.spring()) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Text(question)
                        .font(.headline)
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.leading)
                    
                    Spacer()
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                }
                .padding()
            }
            
            if isExpanded {
                Text(answer)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .padding([.horizontal, .bottom])
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Color("BrandNavy"))
        .cornerRadius(12)
    }
}

// MARK: - Disclaimer View

struct DisclaimerView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Medical Information Disclaimer")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("""
                The information provided in BillGuard is for general informational and educational purposes only. It is not intended to be a substitute for professional medical advice, diagnosis, or treatment.

                **Pricing Information**
                All pricing data shown represents estimates and national averages. Actual costs may vary significantly based on geographic location, specific healthcare provider, insurance coverage, and other factors. Always verify costs directly with your healthcare provider and insurance company.

                **Medical Codes**
                While we strive to provide accurate descriptions of medical codes, the interpretations provided are simplified for general understanding. For precise coding interpretations, please consult a certified medical coder or billing specialist.

                **Not Legal or Financial Advice**
                This app does not provide legal, financial, or insurance advice. For questions about your specific bills, insurance coverage, or potential billing disputes, please consult appropriate professionals.

                **Accuracy**
                While we make every effort to keep information current and accurate, we make no representations or warranties about the completeness, accuracy, or reliability of any information in this app.

                By using this app, you acknowledge and agree to these limitations.
                """)
                .font(.body)
                .lineSpacing(4)
            }
            .padding()
        }
        .navigationTitle("Disclaimer")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Privacy Policy View

struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Privacy Policy")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("""
                **Your Privacy Matters**

                BillGuard is designed with your privacy in mind. We believe your medical information is personal and should stay that way.

                **Data We Don't Collect**
                • We do not collect or store your search queries
                • We do not track which codes you look up
                • We do not require any personal information
                • We do not share any data with third parties

                **Local Storage**
                • Your saved/favorite codes are stored only on your device
                • Your recent searches are stored only on your device
                • Deleting the app removes all locally stored data

                **CloudKit**
                • The app uses Apple's CloudKit to retrieve medical code information
                • No personal data is sent to or stored in CloudKit
                • Only anonymous requests for code data are made

                **No Account Required**
                • You can use all features without creating an account
                • No email, name, or other personal information is required

                **Analytics**
                • We do not use any third-party analytics services
                • We do not track app usage patterns

                **Updates to This Policy**
                We may update this privacy policy from time to time. Any changes will be reflected in the app.

                **Contact**
                If you have questions about this privacy policy, please contact us through the App Store.
                """)
                .font(.body)
                .lineSpacing(4)
            }
            .padding()
        }
        .navigationTitle("Privacy Policy")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Terms View

struct TermsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Terms of Service")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("""
                **Agreement to Terms**

                By downloading, installing, or using BillGuard, you agree to be bound by these Terms of Service.

                **Use of the App**
                • The app is provided for informational purposes only
                • You may not use the app for any illegal or unauthorized purpose
                • You must not misrepresent information obtained from this app as professional medical, legal, or financial advice

                **Intellectual Property**
                • The app, including its content and features, is owned by BillGuard and protected by copyright and other intellectual property laws
                • Medical codes referenced in the app are maintained by their respective governing organizations (AMA for CPT, WHO/CMS for ICD-10, CMS for HCPCS)

                **Limitation of Liability**
                • The app is provided "as is" without warranties of any kind
                • We are not liable for any damages arising from use of the app
                • We are not responsible for any decisions made based on information in the app

                **Termination**
                We reserve the right to terminate or suspend access to the app at any time, without notice, for any reason.

                **Changes to Terms**
                We may modify these terms at any time. Continued use of the app constitutes acceptance of modified terms.

                **Governing Law**
                These terms are governed by applicable law without regard to conflict of law principles.
                """)
                .font(.body)
                .lineSpacing(4)
            }
            .padding()
        }
        .navigationTitle("Terms of Service")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    InfoView()
}
