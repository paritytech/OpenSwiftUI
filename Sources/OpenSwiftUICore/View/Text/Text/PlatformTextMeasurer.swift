//
//  PlatformTextMeasurer.swift
//  OpenSwiftUICore
//
//  Text measurement supplied by a non-Darwin host. Darwin measures with CoreText.
//  Upstream's unmerged TextLayoutBackend (codex/swiftsdl3-backend) is the fuller design:
//  it also carries resolved fonts, which this hook does not.

package import Foundation

package struct PlatformTextMetrics {
    package var size: CGSize
    package var firstBaseline: CGFloat
    package var lastBaseline: CGFloat
    package var numberOfLines: Int

    package init(size: CGSize, firstBaseline: CGFloat, lastBaseline: CGFloat, numberOfLines: Int) {
        self.size = size
        self.firstBaseline = firstBaseline
        self.lastBaseline = lastBaseline
        self.numberOfLines = numberOfLines
    }
}

package enum PlatformTextMeasurer {
    /// Measures `string` laid out in `requestedSize` with at most `lineLimit` lines.
    package nonisolated(unsafe) static var measure: (
        (_ string: NSAttributedString, _ requestedSize: CGSize, _ lineLimit: Int?) -> PlatformTextMetrics
    )?
}
