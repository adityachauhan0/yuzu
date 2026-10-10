import SwiftUI

enum HandoffIllustrationColors {
    static func emptyFill(dark: Bool) -> Color {
        Color(hex: dark ? "#414141" : "#B9C8BD")
    }

    static func emptyStroke(dark: Bool) -> Color {
        Color(hex: dark ? "#EEEEEC" : "#53665A")
    }

    static func waveDivider(dark: Bool) -> Color {
        Color(hex: dark ? "#353535" : "#CBD7CE")
    }

    static func stopwatchHands(dark: Bool) -> Color {
        Color(hex: dark ? "#F2F2F0" : "#F3F5F2")
    }
}

struct ScheduledStopwatchIllustration: View {
    let dark: Bool

    var body: some View {
        ZStack {
            ScheduledStopwatchBody()
                .fill(HandoffIllustrationColors.emptyFill(dark: dark))
                .overlay(
                    ScheduledStopwatchBody()
                        .stroke(HandoffIllustrationColors.emptyStroke(dark: dark), lineWidth: 2.5)
                )
            ScheduledStopwatchHands()
                .stroke(
                    HandoffIllustrationColors.stopwatchHands(dark: dark),
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
                )
        }
        .frame(width: 102, height: 102)
        .accessibilityHidden(true)
    }
}

private struct ScheduledStopwatchBody: Shape {
    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width / 104, rect.height / 104)
        let offsetX = rect.midX - 52 * scale
        let offsetY = rect.midY - 43 * scale

        var path = Path()
        path.addRect(CGRect(x: offsetX + 35 * scale, y: offsetY + 8 * scale, width: 34 * scale, height: 10 * scale))
        path.move(to: CGPoint(x: offsetX + 52 * scale, y: offsetY + 18 * scale))
        path.addLine(to: CGPoint(x: offsetX + 52 * scale, y: offsetY + 27 * scale))
        path.addEllipse(
            in: CGRect(
                x: offsetX + 10 * scale,
                y: offsetY + 28 * scale,
                width: 84 * scale,
                height: 84 * scale
            )
        )
        return path
    }
}

private struct ScheduledStopwatchHands: Shape {
    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width / 104, rect.height / 104)
        let offsetX = rect.midX - 52 * scale
        let offsetY = rect.midY - 43 * scale
        var path = Path()
        path.move(to: CGPoint(x: offsetX + 52 * scale, y: offsetY + 61 * scale))
        path.addLine(to: CGPoint(x: offsetX + 52 * scale, y: offsetY + 28 * scale))
        path.move(to: CGPoint(x: offsetX + 52 * scale, y: offsetY + 61 * scale))
        path.addLine(to: CGPoint(x: offsetX + 74 * scale, y: offsetY + 49 * scale))
        return path
    }
}

struct ScheduledWaveDivider: View {
    let dark: Bool

    var body: some View {
        GeometryReader { geometry in
            let stroke = HandoffIllustrationColors.waveDivider(dark: dark)
            Path { path in
                let period: CGFloat = 14
                let height: CGFloat = 6
                let midY = height / 2
                var x: CGFloat = 0
                while x < geometry.size.width + period {
                    path.move(to: CGPoint(x: x, y: midY))
                    path.addQuadCurve(
                        to: CGPoint(x: x + 7, y: midY),
                        control: CGPoint(x: x + 3.5, y: 0)
                    )
                    path.addQuadCurve(
                        to: CGPoint(x: x + 14, y: midY),
                        control: CGPoint(x: x + 10.5, y: height)
                    )
                    x += period
                }
            }
            .stroke(stroke, lineWidth: 1.3)
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}
