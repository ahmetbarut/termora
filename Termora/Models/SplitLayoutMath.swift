//
//  SplitLayoutMath.swift
//  Termora
//

import CoreGraphics
import Foundation

/// Pure layout math for split panes. Kept out of the view so it can be unit tested.
enum SplitLayoutMath {

    /// Divider hit area / drawn thickness in points.
    static let dividerThickness: CGFloat = 6

    /// Space left for the two panes once the divider is subtracted.
    static func usableLength(totalLength: CGFloat) -> CGFloat {
        max(0, totalLength - dividerThickness)
    }

    static func firstLength(totalLength: CGFloat, ratio: Double) -> CGFloat {
        usableLength(totalLength: totalLength) * CGFloat(ratio)
    }

    static func secondLength(totalLength: CGFloat, ratio: Double) -> CGFloat {
        let usable = usableLength(totalLength: totalLength)
        return usable - usable * CGFloat(ratio)
    }

    /// Converts a divider position (measured inside the usable length) into a clamped ratio.
    static func ratio(atPosition position: CGFloat, totalLength: CGFloat) -> Double {
        guard totalLength > 0 else { return 0.5 }
        let raw = Double(position / totalLength)
        return min(max(raw, PaneNode.ratioRange.lowerBound), PaneNode.ratioRange.upperBound)
    }
}