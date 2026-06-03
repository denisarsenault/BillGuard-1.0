//
//  RegistrationView.swift
//  BillGuard
//
//  New user registration screen
//

import SwiftUI

struct RegistrationView: View {
    
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var userManager: UserManager
    
    @State private var username = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var agreeToTerms = false
    @State private var showPassword = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                Color("BrandDeepNavy").ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Header
                        VStack(spacing: 8) {
                            Text("Create Account")
                                .font(.title)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                            
                            Text("Join BillGuard to manage your medical bills")
                                .font(.body)
                                .foregroundColor(Color("BrandCyan").opacity(0.5))
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, 20)
                        
                        // Form
                        VStack(spacing: 20) {
                            // Username
                            FormField(title: "Username", text: $username)
                                .autocapitalization(.none)
                            
                            // Email
                            FormField(title: "Email", text: $email, keyboardType: .emailAddress)
                                .autocapitalization(.none)
                            
                            // First Name
                            FormField(title: "First Name", text: $firstName)
                            
                            // Last Name
                            FormField(title: "Last Name", text: $lastName)
                            
                            // Password
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Password")
                                    .font(.subheadline)
                                    .foregroundColor(Color("BrandCyan").opacity(0.5))
                                
                                HStack {
                                    if showPassword {
                                        TextField("At least 8 characters", text: $password)
                                    } else {
                                        SecureField("At least 8 characters", text: $password)
                                    }
                                    
                                    Button {
                                        showPassword.toggle()
                                    } label: {
                                        Image(systemName: showPassword ? "eye.slash" : "eye")
                                            .foregroundColor(Color("BrandCyan").opacity(0.5))
                                    }
                                }
                                .padding()
                                .background(Color.white.opacity(0.1))
                                .cornerRadius(12)
                                .foregroundColor(.white)
                                
                                if !password.isEmpty && password.count < 8 {
                                    Text("Password must be at least 8 characters")
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                }
                            }
                            
                            // Confirm Password
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Confirm Password")
                                    .font(.subheadline)
                                    .foregroundColor(Color("BrandCyan").opacity(0.5))
                                
                                SecureField("Re-enter password", text: $confirmPassword)
                                    .padding()
                                    .background(Color.white.opacity(0.1))
                                    .cornerRadius(12)
                                    .foregroundColor(.white)
                                
                                if !confirmPassword.isEmpty && password != confirmPassword {
                                    Text("Passwords do not match")
                                        .font(.caption)
                                        .foregroundColor(.red)
                                }
                            }
                            
                            // Terms Agreement
                            HStack(alignment: .top, spacing: 12) {
                                Button {
                                    agreeToTerms.toggle()
                                } label: {
                                    Image(systemName: agreeToTerms ? "checkmark.square.fill" : "square")
                                        .font(.title3)
                                        .foregroundColor(agreeToTerms ? .teal : .gray)
                                }
                                
                                Text("I agree to the Terms of Service and Privacy Policy")
                                    .font(.subheadline)
                                    .foregroundColor(Color("BrandCyan").opacity(0.5))
                                    .multilineTextAlignment(.leading)
                            }
                            .padding(.top, 8)
                            
                            // Error Message
                            if let error = userManager.errorMessage {
                                Text(error)
                                    .font(.caption)
                                    .foregroundColor(.red)
                                    .multilineTextAlignment(.center)
                            }
                            
                            // Register Button
                            Button {
                                register()
                            } label: {
                                HStack {
                                    if userManager.isLoading {
                                        ProgressView()
                                            .tint(.black)
                                    } else {
                                        Text("Create Account")
                                    }
                                }
                                .font(.title3)
                                .fontWeight(.semibold)
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(isFormValid ? Color("BrandCyan") : Color.gray)
                                .cornerRadius(14)
                            }
                            .disabled(!isFormValid || userManager.isLoading)
                            
                            // Already have account
                            Button {
                                dismiss()
                            } label: {
                                Text("Already have an account? Sign In")
                                    .font(.subheadline)
                                    .foregroundColor(Color("BrandCyan"))
                            }
                            .padding(.top, 8)
                        }
                        .padding(.horizontal, 24)
                        
                        Spacer()
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(Color("BrandCyan").opacity(0.5))
                }
            }
        }
        .preferredColorScheme(.dark)
    }
    
    // MARK: - Validation
    
    private var isFormValid: Bool {
        !username.isEmpty &&
        username.count >= 3 &&
        !email.isEmpty &&
        email.contains("@") &&
        password.count >= 8 &&
        password == confirmPassword &&
        agreeToTerms
    }
    
    // MARK: - Actions
    
    private func register() {
        let data = RegistrationData(
            username: username,
            email: email,
            password: password,
            confirmPassword: confirmPassword,
            firstName: firstName,
            lastName: lastName
        )
        
        Task {
            let result = await userManager.register(data: data)
            
            await MainActor.run {
                switch result {
                case .success:
                    dismiss()
                case .failure:
                    break
                }
            }
        }
    }
}

// MARK: - Form Field Component

struct FormField: View {
    let title: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .foregroundColor(Color("BrandCyan").opacity(0.5))
            
            TextField(title, text: $text)
                .keyboardType(keyboardType)
                .padding()
                .background(Color.white.opacity(0.1))
                .cornerRadius(12)
                .foregroundColor(.white)
        }
    }
}

// MARK: - Preview

#Preview {
    RegistrationView()
        .environmentObject(AppState())
        .environmentObject(UserManager.shared)
}
