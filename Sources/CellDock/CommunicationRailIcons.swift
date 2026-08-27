import SwiftUI

enum CommunicationRailIconKind {
    case messages, recents, recordings, proxy, sim, moduleMode, settings
}

struct AnimatedCommunicationRailButton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let section: PhoneWindowSection
    let icon: CommunicationRailIconKind
    let isSelected: Bool
    let selectionNamespace: Namespace.ID
    let selectionGroup: String
    let action: () -> Void

    @State private var isHovered = false
    @State private var activation: CGFloat = 0
    @State private var rotationDegrees: CGFloat = 0

    var body: some View {
        Button {
            playActivation()
            action()
        } label: {
            ZStack {
                if isHovered && !isSelected {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(Color.primary.opacity(0.055))
                }
                if isSelected {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(Color.accentColor.opacity(0.10))
                        .overlay {
                            RoundedRectangle(cornerRadius: 15, style: .continuous)
                                .strokeBorder(Color.accentColor.opacity(0.18), lineWidth: 0.7)
                        }
                        .matchedGeometryEffect(
                            id: "communicationRailSelection.\(selectionGroup)",
                            in: selectionNamespace
                        )
                }

                CommunicationRailIcon(
                    kind: icon,
                    isHovered: isHovered,
                    activation: activation,
                    rotationDegrees: rotationDegrees,
                    reduceMotion: reduceMotion
                )
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                .frame(width: 22, height: 22)
                .scaleEffect(reduceMotion ? 1 : (isHovered ? 1.04 : 1))
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(CommunicationRailPressStyle(reduceMotion: reduceMotion))
        .onHover { hovering in
            withAnimation(reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.22, dampingFraction: 1)) {
                isHovered = hovering
            }
        }
        .help(section.title)
        .accessibilityLabel(section.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func playActivation() {
        guard !reduceMotion else { return }

        switch icon {
        case .proxy:
            withAnimation(.easeInOut(duration: 0.55)) {
                rotationDegrees += 360
            }
            return
        case .settings:
            withAnimation(.easeInOut(duration: 0.65)) {
                rotationDegrees += 360
            }
            return
        case .messages, .recents, .recordings, .sim, .moduleMode:
            break
        }

        activation = 0
        withAnimation(.easeOut(duration: 0.10)) { activation = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.11) {
            withAnimation(.spring(response: 0.30, dampingFraction: 0.82)) { activation = 0 }
        }
    }
}

private struct CommunicationRailPressStyle: ButtonStyle {
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.94 : 1))
            .animation(
                reduceMotion ? nil : .spring(response: 0.18, dampingFraction: 0.92),
                value: configuration.isPressed
            )
    }
}

private struct CommunicationRailIcon: View {
    let kind: CommunicationRailIconKind
    let isHovered: Bool
    let activation: CGFloat
    let rotationDegrees: CGFloat
    let reduceMotion: Bool

    private var hover: CGFloat { reduceMotion ? 0 : (isHovered ? 1 : 0) }
    private var impulse: CGFloat { reduceMotion ? 0 : activation }

    @ViewBuilder var body: some View {
        switch kind {
        case .messages: messageIcon
        case .recents: phoneIcon
        case .recordings: recordingIcon
        case .proxy: globeIcon
        case .sim: simIcon
        case .moduleMode: moduleModeIcon
        case .settings: settingsIcon
        }
    }

    private var messageIcon: some View {
        ZStack {
            RailIconStroke(.messageBubble)
            ForEach(Array(MessageLineLayer.allCases.enumerated()), id: \.offset) { index, line in
                RailIconStroke(line.shapeLayer)
                    .offset(x: -(hover * CGFloat(3 - index) * 0.28) - impulse * CGFloat(index + 1) * 0.32)
                    .opacity(0.78 + 0.22 * max(hover, impulse))
            }
        }
        .offset(y: -hover * 0.7)
    }

    private var phoneIcon: some View {
        RailIconStroke(.phone)
            .rotationEffect(.degrees(-hover * 5 - impulse * 12))
            .offset(x: impulse * 0.35, y: -hover * 0.7 - impulse * 1.15)
            .scaleEffect(1 + impulse * 0.045)
    }

    private var recordingIcon: some View {
        ZStack {
            ForEach(Array(AudioBarLayer.allCases.enumerated()), id: \.offset) { index, bar in
                RailIconStroke(bar.shapeLayer)
                    .scaleEffect(x: 1, y: 1 + (hover * 0.07 + impulse * 0.14) * audioWeight(index))
                    .animation(
                        .spring(response: 0.26, dampingFraction: 0.84)
                            .delay((hover + impulse) > 0 ? Double(index) * 0.012 : 0),
                        value: hover + impulse
                    )
            }
            RailIconStroke(.microphone)
                .scaleEffect(1 + impulse * 0.07)
            RailIconStroke(.microphoneStem)
        }
    }

    private var globeIcon: some View {
        ZStack {
            RailIconStroke(.globeOuter)
            ZStack {
                RailIconStroke(.globeMeridian)
                RailIconStroke(.globeEquator)
            }
            .rotationEffect(.degrees(hover * 8 + rotationDegrees))
        }
    }

    private var simIcon: some View {
        ZStack {
            RailIconStroke(.simOuter)
            ZStack {
                RailIconStroke(.simChip)
                RailIconStroke(.simContacts)
                    .opacity(0.76 + max(hover, impulse) * 0.24)
            }
            .offset(y: -hover * 0.8 - impulse * 1.2)
            .scaleEffect(1 - impulse * 0.035)
        }
    }

    /// Two arrows passing in opposite directions — the module moving between
    /// hosts. They slide apart on hover so the motion reads as a swap rather
    /// than a refresh, which is what the rotating proxy and settings icons mean.
    private var moduleModeIcon: some View {
        ZStack {
            RailIconStroke(.modeArrowForward)
                .offset(x: hover * 1.1 + impulse * 1.8)
            RailIconStroke(.modeArrowBack)
                .offset(x: -hover * 1.1 - impulse * 1.8)
        }
    }

    private var settingsIcon: some View {
        ZStack {
            RailIconStroke(.cogSpokes)
            RailIconStroke(.cogOuter)
            RailIconStroke(.cogHub)
                .scaleEffect(1 - impulse * 0.10)
        }
        .rotationEffect(.degrees(hover * 15 + rotationDegrees))
    }

    private func audioWeight(_ index: Int) -> CGFloat {
        let center = CGFloat(AudioBarLayer.allCases.count - 1) / 2
        return max(0.45, 1 - abs(CGFloat(index) - center) * 0.12)
    }
}

private enum MessageLineLayer: CaseIterable {
    case top, middle, bottom
    var shapeLayer: RailIconLayer {
        switch self {
        case .top: return .messageTop
        case .middle: return .messageMiddle
        case .bottom: return .messageBottom
        }
    }
}

private enum AudioBarLayer: CaseIterable {
    case farLeft, left, upperCenter, lowerCenter, right, farRight
    var shapeLayer: RailIconLayer {
        switch self {
        case .farLeft: return .audioFarLeft
        case .left: return .audioLeft
        case .upperCenter: return .audioUpperCenter
        case .lowerCenter: return .audioLowerCenter
        case .right: return .audioRight
        case .farRight: return .audioFarRight
        }
    }
}

private enum RailIconLayer {
    case messageBubble, messageTop, messageMiddle, messageBottom
    case phone
    case audioFarLeft, audioLeft, audioUpperCenter, audioLowerCenter, audioRight, audioFarRight
    case microphone, microphoneStem
    case globeOuter, globeMeridian, globeEquator
    case simOuter, simChip, simContacts
    case modeArrowForward, modeArrowBack
    case cogSpokes, cogOuter, cogHub
}

private struct RailIconStroke: View {
    let layer: RailIconLayer
    init(_ layer: RailIconLayer) { self.layer = layer }

    var body: some View {
        RailIconPath(layer: layer)
            .stroke(style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
    }
}

private struct RailIconPath: Shape {
    let layer: RailIconLayer

    func path(in rect: CGRect) -> Path {
        var path = Path()
        switch layer {
        case .messageBubble:
            path.move(to: p(4, 3)); path.addLine(to: p(20, 3))
            path.addQuadCurve(to: p(22, 5), control: p(22, 3)); path.addLine(to: p(22, 17))
            path.addQuadCurve(to: p(20, 19), control: p(22, 19)); path.addLine(to: p(6.83, 19))
            path.addQuadCurve(to: p(5.41, 19.59), control: p(5.83, 19)); path.addLine(to: p(3.21, 21.79))
            path.addQuadCurve(to: p(2, 21.29), control: p(2.5, 22.5)); path.addLine(to: p(2, 5))
            path.addQuadCurve(to: p(4, 3), control: p(2, 3))
        case .messageTop: line(&path, (7, 7), (15, 7))
        case .messageMiddle: line(&path, (7, 11), (17, 11))
        case .messageBottom: line(&path, (7, 15), (13, 15))
        case .phone:
            path.move(to: p(13.832, 16.568))
            path.addQuadCurve(to: p(15.045, 16.265), control: p(14.55, 16.78))
            path.addLine(to: p(15.4, 15.8))
            path.addQuadCurve(to: p(17, 15), control: p(16.02, 15))
            path.addLine(to: p(20, 15))
            path.addQuadCurve(to: p(22, 17), control: p(22, 15))
            path.addLine(to: p(22, 20))
            path.addQuadCurve(to: p(20, 22), control: p(22, 22))
            path.addCurve(to: p(2, 4), control1: p(10.06, 22), control2: p(2, 13.94))
            path.addQuadCurve(to: p(4, 2), control: p(2, 2))
            path.addLine(to: p(7, 2))
            path.addQuadCurve(to: p(9, 4), control: p(9, 2))
            path.addLine(to: p(9, 7))
            path.addQuadCurve(to: p(8.2, 8.6), control: p(9, 8))
            path.addLine(to: p(7.732, 8.951))
            path.addQuadCurve(to: p(7.44, 10.184), control: p(7.2, 9.45))
            path.addCurve(to: p(13.832, 16.568), control1: p(8.74, 13.08), control2: p(10.94, 15.27))
        case .audioFarLeft: line(&path, (2, 10), (2, 13))
        case .audioLeft: line(&path, (6, 6), (6, 17))
        case .audioUpperCenter: line(&path, (10, 3), (10, 5.34))
        case .audioLowerCenter: line(&path, (14, 5), (14, 5.34))
        case .audioRight: line(&path, (18, 5), (18, 18))
        case .audioFarRight: line(&path, (22, 10), (22, 13))
        case .microphone: path.addRoundedRect(in: box(10, 9, 4, 8), cornerSize: CGSize(width: 2, height: 2))
        case .microphoneStem:
            line(&path, (12, 17), (12, 21)); line(&path, (9, 21), (15, 21))
        case .globeOuter: path.addEllipse(in: box(2, 2, 20, 20))
        case .globeMeridian:
            path.move(to: p(12, 2)); path.addCurve(to: p(12, 22), control1: p(4.8, 7.3), control2: p(4.8, 16.7))
            path.move(to: p(12, 2)); path.addCurve(to: p(12, 22), control1: p(19.2, 7.3), control2: p(19.2, 16.7))
        case .globeEquator: line(&path, (2, 12), (22, 12))
        case .simOuter:
            path.move(to: p(6, 2)); path.addLine(to: p(14.17, 2)); path.addLine(to: p(20, 7.83)); path.addLine(to: p(20, 20))
            path.addQuadCurve(to: p(18, 22), control: p(20, 22)); path.addLine(to: p(6, 22))
            path.addQuadCurve(to: p(4, 20), control: p(4, 22)); path.addLine(to: p(4, 4)); path.addQuadCurve(to: p(6, 2), control: p(4, 2))
        case .simChip: path.addRoundedRect(in: box(8, 10, 8, 8), cornerSize: CGSize(width: 1, height: 1))
        case .simContacts:
            line(&path, (8, 14), (16, 14)); line(&path, (12, 14), (12, 18))
        case .modeArrowForward:
            line(&path, (3, 9), (18, 9))
            path.move(to: p(14.5, 5.5)); path.addLine(to: p(18, 9)); path.addLine(to: p(14.5, 12.5))
        case .modeArrowBack:
            line(&path, (6, 15), (21, 15))
            path.move(to: p(9.5, 11.5)); path.addLine(to: p(6, 15)); path.addLine(to: p(9.5, 18.5))
        case .cogOuter: path.addEllipse(in: box(4, 4, 16, 16))
        case .cogHub: path.addEllipse(in: box(10, 10, 4, 4))
        case .cogSpokes:
            let spokes: [((CGFloat, CGFloat), (CGFloat, CGFloat))] = [
                ((12, 2), (12, 4)), ((12, 20), (12, 22)), ((2, 12), (4, 12)), ((20, 12), (22, 12)),
                ((3.34, 7), (5.07, 8)), ((18.93, 16), (20.66, 17)), ((3.34, 17), (5.07, 16)), ((18.93, 8), (20.66, 7)),
                ((7, 3.34), (8, 5.07)), ((16, 18.93), (17, 20.66)), ((7, 20.66), (8, 18.93)), ((16, 5.07), (17, 3.34))
            ]
            for spoke in spokes { line(&path, spoke.0, spoke.1) }
        }

        let transform = CGAffineTransform(translationX: rect.minX, y: rect.minY)
            .scaledBy(x: rect.width / 24, y: rect.height / 24)
        return path.applying(transform)
    }

    private func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
    private func box(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
    private func line(_ path: inout Path, _ start: (CGFloat, CGFloat), _ end: (CGFloat, CGFloat)) {
        path.move(to: p(start.0, start.1)); path.addLine(to: p(end.0, end.1))
    }
}
