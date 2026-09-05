import SonoclesCore
import SwiftUI

/// The mark: concentric arcs opening to the right, from a filled point.
///
/// An amphitheatre seen from above and a sound wave are the same drawing. The
/// arcs are struck from the point rather than centred in the frame, so it reads
/// as something radiating outward from a source rather than as a target.
///
/// Drawn rather than shipped as an asset because it is four strokes, and a
/// vector that scales exactly beats a PDF that needs a build step.
struct SonoclesMark: View {
    var progress: Double = 1
    var lineWidth: CGFloat = 1.6

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let origin = CGPoint(x: side * 0.16, y: side * 0.5)

            ZStack(alignment: .topLeading) {
                Circle()
                    .frame(width: side * 0.17, height: side * 0.17)
                    .position(origin)

                // Three arcs, the outer ones dimmer, so the mark has depth at
                // 16 pt without needing a second colour.
                ForEach(0..<3, id: \.self) { ring in
                    let radius = side * (0.26 + Double(ring) * 0.19)
                    let lit = Double(ring) < progress * 3

                    Path { path in
                        path.addArc(
                            center: origin,
                            radius: radius,
                            startAngle: .degrees(-52),
                            endAngle: .degrees(52),
                            clockwise: false
                        )
                    }
                    .stroke(style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .opacity(lit ? 1 - Double(ring) * 0.15 : 0.16)
                }
            }
            .frame(width: side, height: side)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// State, in a word and a colour, at a glance.
struct StatePill: View {
    let label: String
    let colour: Color

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(colour)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(colour)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            Capsule().fill(colour.opacity(0.11))
        )
    }
}
