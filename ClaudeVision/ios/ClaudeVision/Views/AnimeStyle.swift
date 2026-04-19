import SwiftUI

/// Anime-inspired visual primitives. All fake — built from SwiftUI shapes,
/// gradients, and typography — so we can validate game mechanics now and
/// swap in real key art later without touching layout code.

// MARK: - Typography

extension Font {
    /// Manga-title feel: heavy weight, italic slant, rounded design.
    static func hype(_ size: CGFloat) -> Font {
        .system(size: size, weight: .heavy, design: .rounded).italic()
    }

    /// Score / stat tiles: monospaced digits, huge.
    static func stat(_ size: CGFloat) -> Font {
        .system(size: size, weight: .black, design: .rounded).monospacedDigit()
    }
}

// MARK: - Cel border

/// Thick outline + offset hard shadow — the cel-shaded border found on every
/// anime UI card. Takes a tint so each game keeps its own signature color.
struct CelBorder: ViewModifier {
    var tint: Color
    var radius: CGFloat = Theme.Radius.medium
    var strokeWidth: CGFloat = 3

    func body(content: Content) -> some View {
        content
            .background(
                LinearGradient(
                    colors: [tint.opacity(0.22), Color.black.opacity(0.35)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(tint, lineWidth: strokeWidth)
            )
            .background(
                // Hard offset shadow — no blur, pure offset block.
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Color.black)
                    .offset(x: 4, y: 5)
            )
    }
}

extension View {
    func celBorder(tint: Color, radius: CGFloat = Theme.Radius.medium, strokeWidth: CGFloat = 3) -> some View {
        modifier(CelBorder(tint: tint, radius: radius, strokeWidth: strokeWidth))
    }
}

// MARK: - Speed lines

/// Radiating stripes that emanate from the center. Use as a background behind
/// hero art during active motion — the intensity binding (0..1) fades them.
struct SpeedLines: View {
    var tint: Color
    var intensity: CGFloat
    var lineCount: Int = 18

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            ZStack {
                ForEach(0..<lineCount, id: \.self) { i in
                    Capsule()
                        .fill(tint.opacity(Double(intensity) * 0.55))
                        .frame(width: size * 0.9, height: 2 + CGFloat(i % 3))
                        .rotationEffect(.degrees(Double(i) * (360.0 / Double(lineCount))))
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .mask(
                RadialGradient(
                    colors: [.clear, .black, .black, .clear],
                    center: .center,
                    startRadius: size * 0.18,
                    endRadius: size * 0.55
                )
            )
            .blendMode(.plusLighter)
            .allowsHitTesting(false)
        }
    }
}

// MARK: - Burst badge

/// Jagged star burst shape — the "POW" / "STRIKE!" badge.
struct Burst: Shape {
    var points: Int = 12
    var innerRatio: CGFloat = 0.65

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outerR = min(rect.width, rect.height) / 2
        let innerR = outerR * innerRatio
        let step = .pi * 2 / Double(points * 2)
        for i in 0..<(points * 2) {
            let angle = Double(i) * step - .pi / 2
            let r = i.isMultiple(of: 2) ? outerR : innerR
            let pt = CGPoint(
                x: center.x + CGFloat(cos(angle)) * r,
                y: center.y + CGFloat(sin(angle)) * r
            )
            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }
        path.closeSubpath()
        return path
    }
}

/// Filled burst with text inside — used for score tiles and "STRIKE!" flashes.
struct BurstBadge: View {
    var text: String
    var tint: Color
    var size: CGFloat = 110

    var body: some View {
        ZStack {
            Burst()
                .fill(tint)
                .frame(width: size, height: size)
            Burst()
                .stroke(Color.black, lineWidth: 2)
                .frame(width: size, height: size)
            Text(text)
                .font(.hype(size * 0.28))
                .foregroundColor(.black)
                .rotationEffect(.degrees(-6))
                .padding(.horizontal, 8)
                .minimumScaleFactor(0.5)
        }
        .rotationEffect(.degrees(-8))
        .shadow(color: .black.opacity(0.8), radius: 0, x: 3, y: 4)
    }
}

// MARK: - Halftone dots

/// Faint dot pattern. Tile as a background for a manga-page feel.
struct Halftone: View {
    var color: Color = .white.opacity(0.06)
    var spacing: CGFloat = 14
    var dot: CGFloat = 2

    var body: some View {
        GeometryReader { proxy in
            let cols = Int(proxy.size.width / spacing) + 1
            let rows = Int(proxy.size.height / spacing) + 1
            Canvas { ctx, _ in
                for r in 0..<rows {
                    for c in 0..<cols {
                        let x = CGFloat(c) * spacing + (r.isMultiple(of: 2) ? spacing / 2 : 0)
                        let y = CGFloat(r) * spacing
                        let rect = CGRect(x: x, y: y, width: dot, height: dot)
                        ctx.fill(Path(ellipseIn: rect), with: .color(color))
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}
