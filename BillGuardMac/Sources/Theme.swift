//
//  Theme.swift
//  BillGuard (macOS)
//
//  Brand palette + reusable styling, mirroring the iOS app's design system.
//  The color assets (BrandCyan/BrandNavy/BrandDeepNavy/BrandTeal/AccentColor)
//  are shipped in Assets.xcassets, so these resolve from the catalog and pick
//  up their light/dark variants automatically.
//

import SwiftUI
import BillGuardCore

extension Color {
    static let brandCyan = Color("BrandCyan")
    static let brandNavy = Color("BrandNavy")
    static let brandDeepNavy = Color("BrandDeepNavy")
    static let brandTeal = Color("BrandTeal")

    /// The navy→deep-navy vertical gradient used behind branded chrome on iOS.
    static var brandNavyGradient: LinearGradient {
        LinearGradient(colors: [.brandNavy, .brandDeepNavy],
                       startPoint: .top, endPoint: .bottom)
    }

    /// The cyan→teal accent gradient used on primary actions / logos.
    static var brandAccentGradient: LinearGradient {
        LinearGradient(colors: [.brandCyan, .brandTeal],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// Rounded card surface used throughout the app (matches iOS card styling).
struct BrandCard: ViewModifier {
    var padding: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Color(nsColor: .controlBackgroundColor),
                        in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator))
    }
}

extension View {
    func brandCard(padding: CGFloat = 16) -> some View { modifier(BrandCard(padding: padding)) }
}

extension Color {
    /// App/root background (matches iOS BrandDeepNavy).
    static let brandScreen = Color.brandDeepNavy
    /// Card / control background (matches iOS BrandNavy .cardStyle()).
    static let brandCard = Color.brandNavy

    /// Code-type accent, mirroring the iOS convention.
    static func codeType(_ type: MedicalCodeType) -> Color {
        switch type {
        case .cpt:               return .brandCyan
        case .icd10, .icd10pcs:  return .green
        case .hcpcs:             return .orange
        }
    }
}

// Make the brand colors usable via leading-dot syntax in ShapeStyle contexts
// (.foregroundStyle(.brandCyan), .fill(.codeType(t)), …).
extension ShapeStyle where Self == Color {
    static var brandCyan: Color { Color.brandCyan }
    static var brandTeal: Color { Color.brandTeal }
    static var brandNavy: Color { Color.brandNavy }
    static var brandDeepNavy: Color { Color.brandDeepNavy }
    static var brandScreen: Color { Color.brandScreen }
    static var brandCard: Color { Color.brandCard }
    static func codeType(_ t: MedicalCodeType) -> Color { Color.codeType(t) }
}

/// Fills the whole detail area with the brand background.
struct BrandScreen: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.brandScreen)
    }
}
extension View { func brandScreen() -> some View { modifier(BrandScreen()) } }

/// Rounded navy card on the dark background (matches iOS .cardStyle()).
struct NavyCard: ViewModifier {
    var padding: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Color.brandCard, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.brandCyan.opacity(0.12)))
    }
}
extension View { func navyCard(padding: CGFloat = 16) -> some View { modifier(NavyCard(padding: padding)) } }

/// A monospaced code-type badge (CPT / ICD-10 / HCPCS or a raw code).
struct CodeTypeBadge: View {
    let text: String
    var color: Color = .brandCyan
    var body: some View {
        Text(text)
            .font(.system(.caption, design: .monospaced).bold())
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(color.opacity(0.18), in: RoundedRectangle(cornerRadius: 5))
            .foregroundStyle(color)
    }
}

/// Big branded screen header with logo + title, on the navy gradient.
struct BrandHeader: View {
    let title: String
    var subtitle: String?
    var body: some View {
        HStack(spacing: 12) {
            Image("BrandLogo").resizable().aspectRatio(contentMode: .fit).frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.brandAccentGradient)
                if let subtitle { Text(subtitle).font(.caption).foregroundStyle(Color.brandCyan.opacity(0.7)) }
            }
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(Color.brandNavyGradient)
    }
}

/// The BillGuard wordmark/logo lockup, reused in the sidebar and headers.
struct BrandLogoMark: View {
    var size: CGFloat = 28
    var showsWordmark: Bool = true
    var body: some View {
        HStack(spacing: 8) {
            Image("BrandLogo")
                .resizable().aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
            if showsWordmark {
                Text("BillGuard")
                    .font(.system(size: size * 0.64, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.brandCyan)
            }
        }
    }
}
