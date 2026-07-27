//
//  PaneGeometry.swift
//  Termora
//

import CoreGraphics
import Foundation

enum FocusDirection {
    case left
    case right
    case up
    case down
}

/// Directional pane navigation over on-screen frames.
/// Frames use AppKit coordinates: origin bottom-left, +y up.
enum PaneGeometry {

    /// Layout rounding tolerance in points.
    private static let tolerance: CGFloat = 1

    static func neighbor(of paneID: UUID, direction: FocusDirection, frames: [UUID: CGRect]) -> UUID? {
        guard let source = frames[paneID] else { return nil }

        var best: (id: UUID, overlap: CGFloat, distance: CGFloat, centerDelta: CGFloat)?

        for (candidateID, frame) in frames where candidateID != paneID {
            let overlap: CGFloat
            let distance: CGFloat
            let centerDelta: CGFloat

            switch direction {
            case .right:
                guard frame.minX >= source.maxX - tolerance else { continue }
                overlap = verticalOverlap(source, frame)
                distance = frame.minX - source.maxX
                centerDelta = abs(frame.midY - source.midY)
            case .left:
                guard frame.maxX <= source.minX + tolerance else { continue }
                overlap = verticalOverlap(source, frame)
                distance = source.minX - frame.maxX
                centerDelta = abs(frame.midY - source.midY)
            case .up:
                guard frame.minY >= source.maxY - tolerance else { continue }
                overlap = horizontalOverlap(source, frame)
                distance = frame.minY - source.maxY
                centerDelta = abs(frame.midX - source.midX)
            case .down:
                guard frame.maxY <= source.minY + tolerance else { continue }
                overlap = horizontalOverlap(source, frame)
                distance = source.minY - frame.maxY
                centerDelta = abs(frame.midX - source.midX)
            }

            guard overlap > 0 else { continue }

            guard let incumbent = best else {
                best = (candidateID, overlap, distance, centerDelta)
                continue
            }

            if isBetter(overlap: overlap, distance: distance, centerDelta: centerDelta,
                        than: incumbent) {
                best = (candidateID, overlap, distance, centerDelta)
            }
        }

        return best?.id
    }

    private static func isBetter(overlap: CGFloat,
                                 distance: CGFloat,
                                 centerDelta: CGFloat,
                                 than incumbent: (id: UUID, overlap: CGFloat, distance: CGFloat, centerDelta: CGFloat)) -> Bool {
        let epsilon: CGFloat = 0.001
        if overlap > incumbent.overlap + epsilon { return true }
        if overlap < incumbent.overlap - epsilon { return false }
        if distance < incumbent.distance - epsilon { return true }
        if distance > incumbent.distance + epsilon { return false }
        return centerDelta < incumbent.centerDelta - epsilon
    }

    private static func verticalOverlap(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        max(0, min(lhs.maxY, rhs.maxY) - max(lhs.minY, rhs.minY))
    }

    private static func horizontalOverlap(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        max(0, min(lhs.maxX, rhs.maxX) - max(lhs.minX, rhs.minX))
    }
}
