import SwiftUI

struct MouseSurfaceView: View {
    @Binding var zone: ScrollZone
    var fingers: [FingerDot]
    var handedness: Handedness

    private let mouseSize = CGSize(width: 168, height: 292)

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                mouseBody
                zoneOverlay
                fingerDots
                labels
            }
            .frame(width: mouseSize.width, height: mouseSize.height)
            .contentShape(RoundedRectangle(cornerRadius: 36, style: .continuous))
            .gesture(zoneDrag)
            .accessibilityLabel("Magic Mouse scroll zone")

            Text("Drag the blue area. Only that part of the mouse will scroll.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var mouseBody: some View {
        RoundedRectangle(cornerRadius: 36, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color(white: 0.99),
                        Color(white: 0.90)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay {
                RoundedRectangle(cornerRadius: 36, style: .continuous)
                    .stroke(Color.black.opacity(0.12), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
            .overlay(alignment: .bottom) {
                Capsule()
                    .fill(Color.black.opacity(0.08))
                    .frame(width: 42, height: 6)
                    .padding(.bottom, 14)
            }
    }

    private var zoneOverlay: some View {
        GeometryReader { geo in
            let rect = zoneRect(in: geo.size)
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.accentColor.opacity(0.28))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.accentColor, lineWidth: 2)
                }
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
                .overlay {
                    edgeHandle(at: CGPoint(x: rect.minX, y: rect.midY), size: geo.size)
                    edgeHandle(at: CGPoint(x: rect.maxX, y: rect.midY), size: geo.size)
                }
        }
    }

    private var fingerDots: some View {
        GeometryReader { geo in
            ForEach(fingers) { finger in
                Circle()
                    .fill(finger.inZone ? Color.green : Color.orange)
                    .frame(width: 16, height: 16)
                    .overlay {
                        Circle().stroke(.white, lineWidth: 2)
                    }
                    .shadow(radius: 2)
                    .position(
                        x: finger.x * geo.size.width,
                        y: (1 - finger.y) * geo.size.height
                    )
            }
        }
        .allowsHitTesting(false)
    }

    private var labels: some View {
        GeometryReader { geo in
            Text(handedness.indexLabel)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .position(x: geo.size.width * 0.18, y: geo.size.height * 0.55)
            Text("Middle")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .position(x: geo.size.width * 0.5, y: geo.size.height * 0.22)
            Text(handedness.pinkyLabel)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .position(x: geo.size.width * 0.82, y: geo.size.height * 0.55)
        }
        .allowsHitTesting(false)
    }

    private func edgeHandle(at point: CGPoint, size: CGSize) -> some View {
        Circle()
            .fill(Color.accentColor)
            .frame(width: 10, height: 10)
            .position(point)
            .allowsHitTesting(false)
    }

    private var zoneDrag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                updateZone(translation: value.translation, start: value.startLocation)
            }
            .onEnded { _ in
                dragKind = .none
            }
    }

    @State private var dragKind: DragKind = .none
    @State private var dragOrigin = ScrollZone.middleFinger

    private enum DragKind {
        case none, move, left, right, top, bottom
    }

    private func updateZone(translation: CGSize, start: CGPoint) {
        let size = mouseSize
        let startUnit = CGPoint(x: start.x / size.width, y: 1 - start.y / size.height)
        let slop: Double = 0.06

        if dragKind == .none {
            dragOrigin = zone
            let z = zone
            if abs(startUnit.x - z.minX) < slop {
                dragKind = .left
            } else if abs(startUnit.x - z.maxX) < slop {
                dragKind = .right
            } else if abs(startUnit.y - z.maxY) < slop {
                dragKind = .top
            } else if abs(startUnit.y - z.minY) < slop {
                dragKind = .bottom
            } else if z.contains(x: startUnit.x, y: startUnit.y) {
                dragKind = .move
            } else {
                dragKind = .move
            }
        }

        let dx = Double(translation.width / size.width)
        let dy = -Double(translation.height / size.height)
        var next = dragOrigin
        switch dragKind {
        case .none:
            break
        case .move:
            next.minX = dragOrigin.minX + dx
            next.maxX = dragOrigin.maxX + dx
            next.minY = dragOrigin.minY + dy
            next.maxY = dragOrigin.maxY + dy
        case .left:
            next.minX = dragOrigin.minX + dx
        case .right:
            next.maxX = dragOrigin.maxX + dx
        case .top:
            next.maxY = dragOrigin.maxY + dy
        case .bottom:
            next.minY = dragOrigin.minY + dy
        }
        zone = next.clamped()
    }

    private func zoneRect(in size: CGSize) -> CGRect {
        CGRect(
            x: zone.minX * size.width,
            y: (1 - zone.maxY) * size.height,
            width: zone.width * size.width,
            height: zone.height * size.height
        )
    }
}

extension MouseSurfaceView {
    func resetDrag() {
        dragKind = .none
    }
}
