//
//  PaneFrameConverter.swift
//  Termora
//

import CoreGraphics
import Foundation

/// Converts SwiftUI frames (origin top-left, +y down) into the AppKit layout
/// (origin bottom-left, +y up) that `PaneGeometry` expects.
enum PaneFrameConverter {

    static func appKitFrame(_ frame: CGRect, containerHeight: CGFloat) -> CGRect {
        CGRect(x: frame.minX,
               y: containerHeight - frame.maxY,
               width: frame.width,
               height: frame.height)
    }

    static func appKitFrames(_ frames: [UUID: CGRect], containerHeight: CGFloat) -> [UUID: CGRect] {
        frames.mapValues { appKitFrame($0, containerHeight: containerHeight) }
    }
}