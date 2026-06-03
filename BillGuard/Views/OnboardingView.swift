//
//  OnboardingView.swift
//  BillGuard
//
//  Onboarding screens for new users — branded to match splash screen
//

import SwiftUI

struct OnboardingView: View {
    
    @EnvironmentObject var appState: AppState
    @Binding var hasCompletedOnboarding: Bool
    @State private var currentPage = 0
    
    private let totalPages = 3
    
    var body: some View {
        ZStack {
            // Background — matches splash screen
            Color("BrandDeepNavy")
                .ignoresSafeArea()
            
            // Radial glow
            RadialGradient(
                colors: [
                    Color("BrandCyan").opacity(0.12),
                    Color("BrandNavy").opacity(0.05),
                    Color.clear
                ],
                center: .center,
                startRadius: 30,
                endRadius: 400
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                
                TabView(selection: $currentPage) {
                    OnboardingPage1().tag(0)
                    OnboardingPage2().tag(1)
                    OnboardingPage3().tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut, value: currentPage)
                
                // Page indicator — animated capsule dots
                HStack(spacing: 10) {
                    ForEach(0..<totalPages, id: \.self) { index in
                        Capsule()
                            .fill(currentPage == index
                                  ? Color("BrandCyan")
                                  : Color("BrandCyan").opacity(0.25))
                            .frame(width: currentPage == index ? 24 : 8, height: 8)
                            .animation(.easeInOut(duration: 0.3), value: currentPage)
                    }
                }
                .padding(.top, 20)
                
                Spacer().frame(height: 30)
                
                // Buttons
                VStack(spacing: 16) {
                    if currentPage < totalPages - 1 {
                        Button {
                            withAnimation { currentPage += 1 }
                        } label: {
                            Text("Next")
                                .font(.title3)
                                .fontWeight(.semibold)
                                .foregroundColor(Color("BrandDeepNavy"))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    LinearGradient(
                                        colors: [Color("BrandCyan"), Color("BrandTeal")],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .cornerRadius(14)
                                .shadow(color: Color("BrandCyan").opacity(0.4), radius: 12, y: 4)
                        }
                        
                        Button {
                            completeOnboarding()
                        } label: {
                            Text(currentPage == 0 ? "Skip Onboarding" : "Skip")
                                .font(.body)
                                .foregroundColor(Color("BrandCyan").opacity(0.5))
                        }
                    } else {
                        Button {
                            completeOnboarding()
                        } label: {
                            Text("Get Started")
                                .font(.title3)
                                .fontWeight(.semibold)
                                .foregroundColor(Color("BrandDeepNavy"))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    LinearGradient(
                                        colors: [Color("BrandCyan"), Color("BrandTeal")],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .cornerRadius(14)
                                .shadow(color: Color("BrandCyan").opacity(0.4), radius: 12, y: 4)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 50)
            }
        }
        .preferredColorScheme(.dark)
    }
    
    private func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        withAnimation {
            hasCompletedOnboarding = true
        }
    }
}

// MARK: - Brand Shield Logo

struct BrandShieldLogo: View {
    var size: CGFloat = 120
    
    var body: some View {
        Image("LaunchLogo")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .shadow(color: Color("BrandCyan").opacity(0.5), radius: 20, x: 0, y: 0)
            .shadow(color: Color("BrandCyan").opacity(0.2), radius: 40, x: 0, y: 0)
    }
}

// MARK: - Brand Logo Text

struct BrandLogoText: View {
    var body: some View {
        VStack(spacing: 4) {
            Text("BillGuard")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.white, Color("BrandCyan")],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .shadow(color: Color("BrandCyan").opacity(0.4), radius: 6, x: 0, y: 0)
            
            Text("MD")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(Color("BrandCyan"))
                .tracking(4)
        }
    }
}

// MARK: - Page 1: Understand Your Medical Bills

struct OnboardingPage1: View {
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            BrandShieldLogo(size: 140)
            
            BrandLogoText()
                .padding(.top, 12)
            
            Text("Understand Your\nMedical Bills")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding(.top, 20)
            
            Text("Medical bills can be confusing.\nBillGuard MD makes them clearer.")
                .font(.body)
                .foregroundColor(Color("BrandCyan").opacity(0.6))
                .multilineTextAlignment(.center)
                .lineSpacing(4)
            
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 32)
    }
}

// MARK: - Page 2: We Break It Down

struct OnboardingPage2: View {
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            BrandShieldLogo(size: 120)
            
            BrandLogoText()
                .padding(.top, 12)
            
            Text("We Break It Down")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding(.top, 20)
            
            VStack(spacing: 4) {
                Text("BillGuard MD helps you")
                    .foregroundColor(Color("BrandCyan").opacity(0.6))
                Text("understand:")
                    .foregroundColor(.white)
                    .fontWeight(.medium)
            }
            .font(.body)
            
            VStack(alignment: .leading, spacing: 16) {
                BulletPoint(text: "what", highlight: "you were charged")
                BulletPoint(text: "what", highlight: "the codes mean")
                BulletPoint(text: "what", highlight: "costs are typical")
            }
            .padding(.top, 8)
            
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 32)
    }
}

// MARK: - Bullet Point View

struct BulletPoint: View {
    let text: String
    let highlight: String
    
    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color("BrandCyan"))
                .frame(width: 8, height: 8)
                .shadow(color: Color("BrandCyan").opacity(0.5), radius: 4)
            
            HStack(spacing: 4) {
                Text(text)
                    .foregroundColor(.white)
                    .fontWeight(.medium)
                Text(highlight)
                    .foregroundColor(Color("BrandCyan").opacity(0.6))
            }
            .font(.body)
        }
    }
}

// MARK: - Page 3: Save & Scan

struct OnboardingPage3: View {
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            BrandShieldLogo(size: 120)
            
            BrandLogoText()
                .padding(.top, 12)
            
            Text("Save & Scan")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding(.top, 20)
            
            VStack(alignment: .leading, spacing: 16) {
                FeatureRow(icon: "camera.fill", text: "Scan codes from your bills")
                FeatureRow(icon: "star.fill", text: "Save favorites for quick access")
                FeatureRow(icon: "doc.text.viewfinder", text: "OCR extracts bill details")
                FeatureRow(icon: "chart.bar.fill", text: "Track payments & balances")
            }
            .padding(.top, 8)
            
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 32)
    }
}

// MARK: - Feature Row View

struct FeatureRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(Color("BrandCyan"))
                .frame(width: 30)
                .shadow(color: Color("BrandCyan").opacity(0.3), radius: 4)
            
            Text(text)
                .font(.body)
                .foregroundColor(Color("BrandCyan").opacity(0.7))
        }
    }
}

#Preview {
    OnboardingView(hasCompletedOnboarding: .constant(false))
        .environmentObject(AppState())
}
