//
//  SplashScreen.swift
//  BillGuard
//
//  Splash screen for app launch and 3D loading indicators
//

import SwiftUI

// MARK: - Splash Screen View

struct SplashScreenView: View {
    @State private var isAnimating = false
    @State private var showLogo = false
    @State private var showTitle = false
    @State private var showSubtitle = false
    @State private var pulseScale: CGFloat = 1.0
    
    let onComplete: () -> Void
    
    var body: some View {
        ZStack {
            // Background gradient — matches icon dark navy with star-like particles
            Color("BrandDeepNavy")
                .ignoresSafeArea()
            
            // Radial glow behind logo
            RadialGradient(
                colors: [
                    Color("BrandCyan").opacity(0.25),
                    Color("BrandNavy").opacity(0.1),
                    Color.clear
                ],
                center: .center,
                startRadius: 40,
                endRadius: 300
            )
            .ignoresSafeArea()
            
            // Animated glow rings
            GeometryReader { geometry in
                ZStack {
                    ForEach(0..<3) { index in
                        Circle()
                            .stroke(
                                Color("BrandCyan").opacity(0.15),
                                lineWidth: 1.5
                            )
                            .frame(
                                width: CGFloat(140 + index * 90),
                                height: CGFloat(140 + index * 90)
                            )
                            .scaleEffect(isAnimating ? 1.3 : 0.9)
                            .opacity(isAnimating ? 0.2 : 0.5)
                            .animation(
                                .easeInOut(duration: 2.2)
                                .repeatForever(autoreverses: true)
                                .delay(Double(index) * 0.3),
                                value: isAnimating
                            )
                    }
                }
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2 - 40)
            }
            
            VStack(spacing: 24) {
                Spacer()
                
                // App icon from asset catalog
                Image("LaunchLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 160, height: 160)
                    .shadow(color: Color("BrandCyan").opacity(0.6), radius: 30, x: 0, y: 0)
                    .shadow(color: Color("BrandCyan").opacity(0.3), radius: 60, x: 0, y: 0)
                    .scaleEffect(showLogo ? 1.0 : 0.6)
                    .opacity(showLogo ? 1.0 : 0)
                    .scaleEffect(pulseScale)
                
                // App Title
                VStack(spacing: 6) {
                    Text("BillGuard")
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.white, Color("BrandCyan")],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .shadow(color: Color("BrandCyan").opacity(0.5), radius: 8, x: 0, y: 0)
                    
                    Text("MD")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundColor(Color("BrandCyan"))
                        .tracking(6)
                    
                    Text("Medical Bill Management")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                        .padding(.top, 4)
                }
                .opacity(showTitle ? 1.0 : 0)
                .offset(y: showTitle ? 0 : 20)
                
                Spacer()
                
                // Loading indicator
                HStack(spacing: 12) {
                    Loading3DDotsView()
                    
                    Text("Loading...")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color("BrandCyan").opacity(0.7))
                }
                .opacity(showSubtitle ? 1.0 : 0)
                
                Spacer()
                    .frame(height: 60)
            }
        }
        .onAppear {
            startAnimations()
        }
    }
    
    private func startAnimations() {
        isAnimating = true
        
        // Logo animation
        withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
            showLogo = true
        }
        
        // Title animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.easeOut(duration: 0.5)) {
                showTitle = true
            }
        }
        
        // Subtitle animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            withAnimation(.easeOut(duration: 0.4)) {
                showSubtitle = true
            }
        }
        
        // Pulse animation
        withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
            pulseScale = 1.05
        }
        
        // Complete after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            onComplete()
        }
    }
}

// MARK: - 3D Loading Dots View

struct Loading3DDotsView: View {
    @State private var animating = false
    
    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color("BrandCyan"), Color("BrandCyan").opacity(0.5)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 10, height: 10)
                    .shadow(color: Color("BrandCyan").opacity(0.4), radius: 3, x: 0, y: 0)
                    .offset(y: animating ? -8 : 0)
                    .animation(
                        .easeInOut(duration: 0.5)
                        .repeatForever(autoreverses: true)
                        .delay(Double(index) * 0.15),
                        value: animating
                    )
            }
        }
        .onAppear {
            animating = true
        }
    }
}

// MARK: - 3D Spinning Ring Loader

struct Loading3DRingView: View {
    @State private var rotation: Double = 0
    @State private var innerRotation: Double = 0
    
    let size: CGFloat
    let color: Color
    let lineWidth: CGFloat
    
    init(size: CGFloat = 50, color: Color = .accentColor, lineWidth: CGFloat = 4) {
        self.size = size
        self.color = color
        self.lineWidth = lineWidth
    }
    
    var body: some View {
        ZStack {
            // Outer ring
            Circle()
                .stroke(
                    AngularGradient(
                        colors: [color, color.opacity(0.3), color.opacity(0.1), .clear],
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360)
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .frame(width: size, height: size)
                .rotationEffect(.degrees(rotation))
                .rotation3DEffect(.degrees(60), axis: (x: 1, y: 0, z: 0))
            
            // Inner ring
            Circle()
                .stroke(
                    AngularGradient(
                        colors: [color.opacity(0.8), color.opacity(0.2), .clear],
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360)
                    ),
                    style: StrokeStyle(lineWidth: lineWidth * 0.7, lineCap: .round)
                )
                .frame(width: size * 0.6, height: size * 0.6)
                .rotationEffect(.degrees(innerRotation))
                .rotation3DEffect(.degrees(-45), axis: (x: 1, y: 0, z: 0))
        }
        .onAppear {
            withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                rotation = 360
            }
            withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) {
                innerRotation = -360
            }
        }
    }
}

// MARK: - 3D Pulsing Shield Loader (BillGuard themed)

struct LoadingShieldView: View {
    @State private var scale: CGFloat = 1.0
    @State private var opacity: Double = 1.0
    @State private var rotation: Double = 0
    
    let size: CGFloat
    
    init(size: CGFloat = 60) {
        self.size = size
    }
    
    var body: some View {
        ZStack {
            // Pulse rings
            ForEach(0..<3) { index in
                Circle()
                    .stroke(Color.accentColor.opacity(0.3), lineWidth: 2)
                    .frame(width: size + CGFloat(index * 20), height: size + CGFloat(index * 20))
                    .scaleEffect(scale)
                    .opacity(max(0, opacity - Double(index) * 0.2))
            }
            
            // Shield icon
            ZStack {
                // Shadow
                Image(systemName: "shield.fill")
                    .font(.system(size: size * 0.6))
                    .foregroundColor(.black.opacity(0.2))
                    .offset(x: 2, y: 2)
                
                // Main shield
                Image(systemName: "shield.fill")
                    .font(.system(size: size * 0.6))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.accentColor, Color.accentColor.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                // Dollar sign
                Text("$")
                    .font(.system(size: size * 0.25, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .offset(y: 1)
            }
            .rotation3DEffect(.degrees(rotation), axis: (x: 0, y: 1, z: 0))
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                scale = 1.3
                opacity = 0.3
            }
            withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                rotation = 15
            }
        }
    }
}

// MARK: - Loading Overlay View

struct LoadingOverlayView: View {
    let message: String
    let style: LoadingStyle
    
    enum LoadingStyle {
        case dots
        case ring
        case shield
    }
    
    init(message: String = "Loading...", style: LoadingStyle = .shield) {
        self.message = message
        self.style = style
    }
    
    var body: some View {
        ZStack {
            // Blur background
            Color.black.opacity(0.4)
                .ignoresSafeArea()
            
            // Loading card
            VStack(spacing: 20) {
                switch style {
                case .dots:
                    Loading3DDotsView()
                        .scaleEffect(1.5)
                case .ring:
                    Loading3DRingView(size: 60, color: .accentColor)
                case .shield:
                    LoadingShieldView(size: 70)
                }
                
                Text(message)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .padding(40)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
            )
        }
    }
}

// MARK: - View Extension for Loading

extension View {
    /// Shows loading overlay immediately when isLoading becomes true
    func loadingOverlay(isLoading: Bool, message: String = "Loading...", style: LoadingOverlayView.LoadingStyle = .shield) -> some View {
        ZStack {
            self
            
            if isLoading {
                LoadingOverlayView(message: message, style: style)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: isLoading)
    }
    
    /// Shows loading overlay only if the operation takes longer than `delay` seconds.
    /// Use this for operations that *might* be fast — the spinner won't flash for quick loads.
    func delayedLoadingOverlay(isLoading: Bool, delay: TimeInterval = 2.0, message: String = "Loading...", style: LoadingOverlayView.LoadingStyle = .shield) -> some View {
        self.modifier(DelayedLoadingModifier(isLoading: isLoading, delay: delay, message: message, style: style))
    }
}

/// ViewModifier that waits `delay` seconds before showing the loading overlay.
/// If the operation completes before the delay, no spinner is ever shown.
struct DelayedLoadingModifier: ViewModifier {
    let isLoading: Bool
    let delay: TimeInterval
    let message: String
    let style: LoadingOverlayView.LoadingStyle
    
    @State private var showOverlay = false
    @State private var delayTask: Task<Void, Never>?
    
    func body(content: Content) -> some View {
        ZStack {
            content
            
            if showOverlay {
                LoadingOverlayView(message: message, style: style)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: showOverlay)
        .onChange(of: isLoading) { _, loading in
            if loading {
                // Start countdown — only show overlay if still loading after delay
                delayTask?.cancel()
                delayTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    if !Task.isCancelled && isLoading {
                        showOverlay = true
                    }
                }
            } else {
                // Loading finished — cancel countdown, hide overlay
                delayTask?.cancel()
                delayTask = nil
                showOverlay = false
            }
        }
    }
}

// MARK: - Preview

#Preview("Splash Screen") {
    SplashScreenView {
        print("Splash complete")
    }
}

#Preview("Loading Indicators") {
    VStack(spacing: 40) {
        Loading3DDotsView()
        Loading3DRingView()
        LoadingShieldView()
    }
    .padding()
}

#Preview("Loading Overlay") {
    Text("Content behind")
        .loadingOverlay(isLoading: true, message: "Processing bill...")
}
