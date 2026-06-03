//
//  LoginView.swift
//  BillGuard
//
//  User login screen
//

import SwiftUI

struct LoginView: View {
    
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var userManager: UserManager
    
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var showingRegistration = false
    @State private var showingForgotPassword = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background gradient
                LinearGradient(
                    colors: [
                        Color("BrandDeepNavy"),
                        Color("BrandNavy")
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 32) {
                        Spacer()
                            .frame(height: 40)
                        
                        // Logo
                        VStack(spacing: 16) {
                            BrandShieldLogo(size: 100)
                            BrandLogoText()
                        }
                        
                        // Welcome Text
                        VStack(spacing: 8) {
                            Text("Welcome Back")
                                .font(.title)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                            
                            Text("Sign in to access your medical bills")
                                .font(.body)
                                .foregroundColor(Color("BrandCyan").opacity(0.5))
                        }
                        .padding(.top, 20)
                        
                        // Login Form
                        VStack(spacing: 20) {
                            // Username Field
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Username")
                                    .font(.subheadline)
                                    .foregroundColor(Color("BrandCyan").opacity(0.5))
                                
                                TextField("Enter username", text: $username)
                                    .textFieldStyle(DarkTextFieldStyle())
                                    .textContentType(.username)
                                    .autocapitalization(.none)
                                    .autocorrectionDisabled()
                            }
                            
                            // Password Field
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Password")
                                    .font(.subheadline)
                                    .foregroundColor(Color("BrandCyan").opacity(0.5))
                                
                                SecureField("Enter password", text: $password)
                                    .textFieldStyle(DarkTextFieldStyle())
                                    .textContentType(.password)
                            }
                            
                            // Error Message
                            if let error = userManager.errorMessage {
                                Text(error)
                                    .font(.caption)
                                    .foregroundColor(.red)
                                    .multilineTextAlignment(.center)
                            }
                            
                            // Login Button
                            Button {
                                login()
                            } label: {
                                HStack {
                                    if userManager.isLoading {
                                        ProgressView()
                                            .tint(.black)
                                    } else {
                                        Text("Sign In")
                                    }
                                }
                                .font(.title3)
                                .fontWeight(.semibold)
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Color("BrandCyan"))
                                .cornerRadius(14)
                            }
                            .disabled(username.isEmpty || password.isEmpty || userManager.isLoading)
                            .opacity((username.isEmpty || password.isEmpty) ? 0.6 : 1)
                            
                            // Forgot Password Link
                            Button {
                                showingForgotPassword = true
                            } label: {
                                Text("Forgot Password?")
                                    .font(.subheadline)
                                    .foregroundColor(Color("BrandCyan").opacity(0.5))
                            }
                            .padding(.top, 8)
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 20)
                        
                        // Register Link
                        VStack(spacing: 12) {
                            Text("Don't have an account?")
                                .foregroundColor(Color("BrandCyan").opacity(0.5))
                            
                            Button {
                                showingRegistration = true
                            } label: {
                                Text("Create Account")
                                    .fontWeight(.semibold)
                                    .foregroundColor(Color("BrandCyan"))
                            }
                        }
                        .padding(.top, 20)
                        
                        Spacer()
                    }
                }
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showingRegistration) {
                RegistrationView()
                    .environmentObject(appState)
                    .environmentObject(userManager)
            }
            .sheet(isPresented: $showingForgotPassword) {
                ForgotPasswordView()
                    .environmentObject(userManager)
            }
        }
        .preferredColorScheme(.dark)
    }
    
    private func login() {
        Task {
            _ = await userManager.login(username: username, password: password)
            // RootView handles the state change via onChange
        }
    }
}

// MARK: - Dark Text Field Style

struct DarkTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding()
            .background(Color("BrandCyan").opacity(0.08))
            .cornerRadius(12)
            .foregroundColor(.white)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color("BrandCyan").opacity(0.15), lineWidth: 1)
            )
    }
}

// MARK: - Forgot Password View

struct ForgotPasswordView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var userManager: UserManager
    
    @State private var username = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var currentStep = 0
    @State private var errorMessage: String?
    @State private var showSuccess = false
    @State private var isLoading = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color("BrandDeepNavy").ignoresSafeArea()
                
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: currentStep == 0 ? "person.badge.key" : "key.fill")
                            .font(.system(size: 50))
                            .foregroundColor(Color("BrandCyan"))
                        
                        Text(currentStep == 0 ? "Reset Password" : "Create New Password")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        
                        Text(currentStep == 0 
                             ? "Enter your username to reset your password" 
                             : "Enter your new password")
                            .font(.body)
                            .foregroundColor(Color("BrandCyan").opacity(0.5))
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 40)
                    
                    // Form
                    VStack(spacing: 20) {
                        if currentStep == 0 {
                            // Step 1: Enter username
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Username")
                                    .font(.subheadline)
                                    .foregroundColor(Color("BrandCyan").opacity(0.5))
                                
                                TextField("Enter your username", text: $username)
                                    .textFieldStyle(DarkTextFieldStyle())
                                    .autocapitalization(.none)
                                    .autocorrectionDisabled()
                            }
                        } else {
                            // Step 2: Enter new password
                            VStack(alignment: .leading, spacing: 8) {
                                Text("New Password")
                                    .font(.subheadline)
                                    .foregroundColor(Color("BrandCyan").opacity(0.5))
                                
                                SecureField("At least 8 characters", text: $newPassword)
                                    .textFieldStyle(DarkTextFieldStyle())
                                
                                if !newPassword.isEmpty && newPassword.count < 8 {
                                    Text("Password must be at least 8 characters")
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                }
                            }
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Confirm Password")
                                    .font(.subheadline)
                                    .foregroundColor(Color("BrandCyan").opacity(0.5))
                                
                                SecureField("Re-enter password", text: $confirmPassword)
                                    .textFieldStyle(DarkTextFieldStyle())
                                
                                if !confirmPassword.isEmpty && newPassword != confirmPassword {
                                    Text("Passwords do not match")
                                        .font(.caption)
                                        .foregroundColor(.red)
                                }
                            }
                        }
                        
                        // Error Message
                        if let error = errorMessage {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                                .multilineTextAlignment(.center)
                        }
                        
                        // Action Button
                        Button {
                            if currentStep == 0 {
                                verifyUsername()
                            } else {
                                resetPassword()
                            }
                        } label: {
                            HStack {
                                if isLoading {
                                    ProgressView()
                                        .tint(.black)
                                } else {
                                    Text(currentStep == 0 ? "Continue" : "Reset Password")
                                }
                            }
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(isButtonEnabled ? Color("BrandCyan") : Color.gray)
                            .cornerRadius(14)
                        }
                        .disabled(!isButtonEnabled || isLoading)
                    }
                    .padding(.horizontal, 24)
                    
                    Spacer()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        if currentStep > 0 {
                            currentStep = 0
                            errorMessage = nil
                        } else {
                            dismiss()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text(currentStep > 0 ? "Back" : "Cancel")
                        }
                        .foregroundColor(Color("BrandCyan").opacity(0.5))
                    }
                }
            }
            .alert("Password Reset", isPresented: $showSuccess) {
                Button("OK") {
                    dismiss()
                }
            } message: {
                Text("Your password has been reset successfully. You can now sign in with your new password.")
            }
        }
        .preferredColorScheme(.dark)
    }
    
    private var isButtonEnabled: Bool {
        if currentStep == 0 {
            return !username.isEmpty
        } else {
            return newPassword.count >= 8 && newPassword == confirmPassword
        }
    }
    
    private func verifyUsername() {
        isLoading = true
        errorMessage = nil
        
        // Check if username exists
        if userManager.userExists(username: username) {
            isLoading = false
            currentStep = 1
        } else {
            isLoading = false
            errorMessage = "No account found with that username"
        }
    }
    
    private func resetPassword() {
        isLoading = true
        errorMessage = nil
        
        let result = userManager.resetPassword(username: username, newPassword: newPassword)
        
        isLoading = false
        
        switch result {
        case .success:
            showSuccess = true
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Preview

#Preview {
    LoginView()
        .environmentObject(AppState())
        .environmentObject(UserManager.shared)
}
