import Foundation

struct ScrollZone: Codable, Equatable {
    var minX: Double
    var maxX: Double
    var minY: Double
    var maxY: Double

    static let middleFinger = ScrollZone(minX: 0.34, maxX: 0.66, minY: 0.10, maxY: 1.0)
    static let narrowCenter = ScrollZone(minX: 0.40, maxX: 0.60, minY: 0.12, maxY: 1.0)
    static let fullSurface = ScrollZone(minX: 0.0, maxX: 1.0, minY: 0.0, maxY: 1.0)

    var width: Double { max(0.04, maxX - minX) }
    var height: Double { max(0.04, maxY - minY) }
    var centerX: Double { (minX + maxX) / 2 }
    var centerY: Double { (minY + maxY) / 2 }

    func contains(x: Double, y: Double) -> Bool {
        x >= minX && x <= maxX && y >= minY && y <= maxY
    }

    func clamped() -> ScrollZone {
        var minX = self.minX.clamped(to: 0...0.96)
        var maxX = self.maxX.clamped(to: 0.04...1)
        var minY = self.minY.clamped(to: 0...0.96)
        var maxY = self.maxY.clamped(to: 0.04...1)
        if maxX - minX < 0.08 {
            let mid = ((minX + maxX) / 2).clamped(to: 0.04...0.96)
            minX = mid - 0.04
            maxX = mid + 0.04
        }
        if maxY - minY < 0.08 {
            let mid = ((minY + maxY) / 2).clamped(to: 0.04...0.96)
            minY = mid - 0.04
            maxY = mid + 0.04
        }
        return ScrollZone(
            minX: min(minX, maxX - 0.08),
            maxX: max(maxX, minX + 0.08),
            minY: min(minY, maxY - 0.08),
            maxY: max(maxY, minY + 0.08)
        )
    }

    func settingWidth(_ width: Double, around center: Double? = nil) -> ScrollZone {
        let center = center ?? centerX
        let half = max(0.04, width / 2)
        return ScrollZone(
            minX: center - half,
            maxX: center + half,
            minY: minY,
            maxY: maxY
        ).clamped()
    }

    func settingCenterX(_ center: Double) -> ScrollZone {
        settingWidth(width, around: center)
    }
}

struct FingerDot: Identifiable, Equatable {
    var id: Int
    var x: Double
    var y: Double
    var speed: Double
    var inZone: Bool
}

enum Handedness: String, Codable, CaseIterable, Identifiable {
    case right
    case left

    var id: String { rawValue }

    var indexLabel: String { self == .right ? "Index" : "Pinky" }
    var pinkyLabel: String { self == .right ? "Pinky" : "Index" }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
