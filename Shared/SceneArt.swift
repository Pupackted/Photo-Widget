import SwiftUI

/// Little hand-drawn "photos" used wherever we need imagery before the user has any:
/// the widget gallery, onboarding and empty states. Built from plain shapes so they
/// render anywhere, including inside widgets.
nonisolated enum SceneKind: Int, CaseIterable, Identifiable, Sendable {
    case sunset, ocean, alpine, night, meadow

    var id: Int { rawValue }

    var caption: String {
        switch self {
        case .sunset: "Golden hour"
        case .ocean: "Summer ’25"
        case .alpine: "Up north"
        case .night: "Late nights"
        case .meadow: "Sunday walk"
        }
    }

    var averageColor: RGBColor {
        switch self {
        case .sunset: RGBColor(red: 0.85, green: 0.45, blue: 0.42)
        case .ocean: RGBColor(red: 0.45, green: 0.7, blue: 0.85)
        case .alpine: RGBColor(red: 0.35, green: 0.45, blue: 0.6)
        case .night: RGBColor(red: 0.15, green: 0.17, blue: 0.35)
        case .meadow: RGBColor(red: 0.55, green: 0.72, blue: 0.5)
        }
    }
}

struct SceneArt: View {
    var kind: SceneKind

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let unit = min(size.width, size.height)
            ZStack {
                switch kind {
                case .sunset: sunset(size, unit)
                case .ocean: ocean(size, unit)
                case .alpine: alpine(size, unit)
                case .night: night(size, unit)
                case .meadow: meadow(size, unit)
                }
            }
            .frame(width: size.width, height: size.height)
            .clipped()
        }
    }

    @ViewBuilder
    private func sunset(_ size: CGSize, _ unit: CGFloat) -> some View {
        LinearGradient(colors: [hex(0x2B1B4F), hex(0x8E3A6E), hex(0xE0645C), hex(0xF8B26A), hex(0xFCD892)],
                       startPoint: .top, endPoint: .bottom)
        sun(center: CGPoint(x: size.width * 0.64, y: size.height * 0.64), diameter: unit * 0.34,
            colors: [hex(0xFFF1C1), hex(0xFFB96B)], glow: hex(0xFFC27A))
        Ridge(points: [0.72, 0.62, 0.68, 0.58, 0.66, 0.6], baseline: 1)
            .fill(LinearGradient(colors: [hex(0x9A4A74), hex(0x6E3462)], startPoint: .top, endPoint: .bottom))
        Ridge(points: [0.86, 0.76, 0.8, 0.72, 0.84], baseline: 1)
            .fill(LinearGradient(colors: [hex(0x4A2150), hex(0x2A1236)], startPoint: .top, endPoint: .bottom))
    }

    @ViewBuilder
    private func ocean(_ size: CGSize, _ unit: CGFloat) -> some View {
        LinearGradient(colors: [hex(0x5FB0EC), hex(0xA9DBFA), hex(0xFFE4CC)], startPoint: .top, endPoint: .center)
        sun(center: CGPoint(x: size.width * 0.3, y: size.height * 0.5), diameter: unit * 0.22,
            colors: [.white, hex(0xFFF3C4)], glow: .white)
        LinearGradient(colors: [hex(0x3C9AD0), hex(0x1D5E93), hex(0x123F6B)], startPoint: .top, endPoint: .bottom)
            .frame(height: size.height * 0.44)
            .frame(maxHeight: .infinity, alignment: .bottom)
        VStack(spacing: unit * 0.035) {
            ForEach(0..<4, id: \.self) { i in
                Capsule()
                    .fill(.white.opacity(0.55 - Double(i) * 0.1))
                    .frame(width: unit * (0.22 - CGFloat(i) * 0.03), height: max(unit * 0.012, 1))
            }
        }
        .position(x: size.width * 0.3, y: size.height * 0.66)
        Ridge(points: [0.9, 0.84, 0.88, 0.95], baseline: 1)
            .fill(hex(0xF3D9B1))
    }

    @ViewBuilder
    private func alpine(_ size: CGSize, _ unit: CGFloat) -> some View {
        LinearGradient(colors: [hex(0x1D3557), hex(0x457B9D), hex(0xF1C6A8)], startPoint: .top, endPoint: .bottom)
        Peaks(peaks: [(0.2, 0.34), (0.55, 0.22), (0.88, 0.38)], baseline: 0.8)
            .fill(LinearGradient(colors: [hex(0x6C8EB5), hex(0x3D5A80)], startPoint: .top, endPoint: .bottom))
        Peaks(peaks: [(0.2, 0.34), (0.55, 0.22), (0.88, 0.38)], baseline: 0.8, capDepth: 0.1)
            .fill(.white.opacity(0.92))
        Ridge(points: [0.8, 0.74, 0.82, 0.76, 0.8], baseline: 1)
            .fill(LinearGradient(colors: [hex(0x2D4262), hex(0x1B2A40)], startPoint: .top, endPoint: .bottom))
    }

    @ViewBuilder
    private func night(_ size: CGSize, _ unit: CGFloat) -> some View {
        LinearGradient(colors: [hex(0x070B1F), hex(0x18254F), hex(0x46427A)], startPoint: .top, endPoint: .bottom)
        ForEach(0..<18, id: \.self) { i in
            let x = (sin(Double(i) * 12.9898) * 43758.5453).truncatingRemainder(dividingBy: 1)
            let y = (sin(Double(i) * 78.233) * 12543.123).truncatingRemainder(dividingBy: 1)
            Circle()
                .fill(.white.opacity(0.5 + abs(x) * 0.5))
                .frame(width: unit * (0.008 + abs(y) * 0.01))
                .position(x: size.width * abs(x), y: size.height * abs(y) * 0.6)
        }
        Circle()
            .fill(hex(0xF6F1DC))
            .frame(width: unit * 0.2)
            .overlay(alignment: .topTrailing) {
                Circle().fill(hex(0x18254F)).frame(width: unit * 0.17).offset(x: unit * 0.05, y: -unit * 0.03)
            }
            .shadow(color: hex(0xF6F1DC).opacity(0.6), radius: unit * 0.08)
            .position(x: size.width * 0.72, y: size.height * 0.3)
        Ridge(points: [0.78, 0.7, 0.76, 0.68, 0.74], baseline: 1)
            .fill(hex(0x1A1840))
        Ridge(points: [0.9, 0.84, 0.88, 0.82], baseline: 1)
            .fill(hex(0x0C0B24))
    }

    @ViewBuilder
    private func meadow(_ size: CGSize, _ unit: CGFloat) -> some View {
        LinearGradient(colors: [hex(0x8FD0E8), hex(0xD7EEF0), hex(0xFBF4DE)], startPoint: .top, endPoint: .bottom)
        sun(center: CGPoint(x: size.width * 0.78, y: size.height * 0.26), diameter: unit * 0.18,
            colors: [.white, hex(0xFFF0B8)], glow: .white)
        Ridge(points: [0.66, 0.58, 0.64, 0.6, 0.68], baseline: 1)
            .fill(LinearGradient(colors: [hex(0xA6CF7C), hex(0x7DB35A)], startPoint: .top, endPoint: .bottom))
        Ridge(points: [0.82, 0.74, 0.8, 0.86], baseline: 1)
            .fill(LinearGradient(colors: [hex(0x6FA548), hex(0x4A7D32)], startPoint: .top, endPoint: .bottom))
    }

    private func sun(center: CGPoint, diameter: CGFloat, colors: [Color], glow: Color) -> some View {
        Circle()
            .fill(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
            .frame(width: diameter, height: diameter)
            .shadow(color: glow.opacity(0.7), radius: diameter * 0.35)
            .position(center)
    }

    private func hex(_ value: UInt32) -> Color {
        Color(red: Double((value >> 16) & 0xFF) / 255,
              green: Double((value >> 8) & 0xFF) / 255,
              blue: Double(value & 0xFF) / 255)
    }
}

/// A soft rolling horizon through evenly spaced heights (fractions of the height, 0 = top).
private struct Ridge: Shape {
    var points: [CGFloat]
    var baseline: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard points.count > 1 else { return path }
        let step = rect.width / CGFloat(points.count - 1)
        let coords = points.enumerated().map { CGPoint(x: rect.minX + CGFloat($0.offset) * step, y: rect.minY + $0.element * rect.height) }
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + baseline * rect.height))
        path.addLine(to: coords[0])
        for i in 1..<coords.count {
            let mid = CGPoint(x: (coords[i - 1].x + coords[i].x) / 2, y: (coords[i - 1].y + coords[i].y) / 2)
            path.addQuadCurve(to: mid, control: coords[i - 1])
        }
        path.addLine(to: coords[coords.count - 1])
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + baseline * rect.height))
        path.closeSubpath()
        return path
    }
}

/// Mountain peaks; with `capDepth` it draws just the snowy tips.
private struct Peaks: Shape {
    var peaks: [(x: CGFloat, y: CGFloat)]
    var baseline: CGFloat
    var capDepth: CGFloat?

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let base = rect.minY + baseline * rect.height
        for peak in peaks {
            let top = CGPoint(x: rect.minX + peak.x * rect.width, y: rect.minY + peak.y * rect.height)
            let halfWidth = (base - top.y) * 0.9
            if let capDepth {
                let depth = capDepth * rect.height
                let ratio = depth / (base - top.y)
                path.move(to: top)
                path.addLine(to: CGPoint(x: top.x + halfWidth * ratio, y: top.y + depth))
                path.addLine(to: CGPoint(x: top.x + halfWidth * ratio * 0.3, y: top.y + depth * 0.75))
                path.addLine(to: CGPoint(x: top.x - halfWidth * ratio * 0.2, y: top.y + depth * 0.95))
                path.addLine(to: CGPoint(x: top.x - halfWidth * ratio, y: top.y + depth))
                path.closeSubpath()
            } else {
                path.move(to: CGPoint(x: top.x - halfWidth, y: base))
                path.addLine(to: top)
                path.addLine(to: CGPoint(x: top.x + halfWidth, y: base))
                path.closeSubpath()
            }
        }
        return path
    }
}
