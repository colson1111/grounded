import SwiftUI

/// Simple anchor glyph — SF Symbol `anchor` is not available on all OS versions.
struct GroundedAnchorIcon: View {
    var size: CGFloat = 16
    var color: Color = GroundedTheme.calmGreen

    var body: some View {
        GroundedAnchorShape()
            .fill(color)
            .frame(width: size * 0.72, height: size)
            .accessibilityLabel("Anchor")
    }
}

private struct GroundedAnchorShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        let cx = rect.midX
        let stroke = max(w * 0.14, 1.2)

        // Ring at top
        let ringRadius = w * 0.18
        let ringCenter = CGPoint(x: cx, y: h * 0.12 + ringRadius)
        path.addEllipse(in: CGRect(
            x: ringCenter.x - ringRadius,
            y: ringCenter.y - ringRadius,
            width: ringRadius * 2,
            height: ringRadius * 2
        ))

        // Shank (vertical stem)
        path.addRoundedRect(
            in: CGRect(x: cx - stroke / 2, y: ringCenter.y + ringRadius * 0.55, width: stroke, height: h * 0.34),
            cornerSize: CGSize(width: stroke / 2, height: stroke / 2)
        )

        // Stock (crossbar)
        let stockY = h * 0.44
        path.addRoundedRect(
            in: CGRect(x: w * 0.08, y: stockY, width: w * 0.84, height: stroke),
            cornerSize: CGSize(width: stroke / 2, height: stroke / 2)
        )

        // Crown
        path.addRoundedRect(
            in: CGRect(x: cx - stroke / 2, y: stockY + stroke, width: stroke, height: h * 0.12),
            cornerSize: CGSize(width: stroke / 2, height: stroke / 2)
        )

        // Flukes (left and right arms)
        let crownBottom = stockY + stroke + h * 0.12
        let arm = stroke * 0.9

        path.move(to: CGPoint(x: cx, y: crownBottom))
        path.addQuadCurve(
            to: CGPoint(x: w * 0.04, y: h * 0.96),
            control: CGPoint(x: w * 0.02, y: h * 0.62)
        )
        path.addQuadCurve(
            to: CGPoint(x: cx, y: crownBottom + arm),
            control: CGPoint(x: w * 0.08, y: h * 0.82)
        )
        path.closeSubpath()

        path.move(to: CGPoint(x: cx, y: crownBottom))
        path.addQuadCurve(
            to: CGPoint(x: w * 0.96, y: h * 0.96),
            control: CGPoint(x: w * 0.98, y: h * 0.62)
        )
        path.addQuadCurve(
            to: CGPoint(x: cx, y: crownBottom + arm),
            control: CGPoint(x: w * 0.92, y: h * 0.82)
        )
        path.closeSubpath()

        return path
    }
}
