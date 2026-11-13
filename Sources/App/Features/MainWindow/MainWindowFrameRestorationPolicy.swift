// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CoreGraphics

enum MainWindowFrameRestorationPolicy {
	static func repairedFrame(
		_ frame: CGRect,
		minimumSize: CGSize,
		minimumVisibleSize: CGSize,
		visibleScreenFrames: [CGRect]
	) -> CGRect {
		let frameIsFinite = [frame.minX, frame.minY, frame.width, frame.height].allSatisfy(\.isFinite)
		var candidate = frameIsFinite ? frame.standardized : CGRect(origin: .zero, size: minimumSize)
		let intersections = visibleScreenFrames.map { screenFrame in
			(screenFrame, intersectionArea(of: candidate, with: screenFrame))
		}
		let bestScreenOverlap = intersections.max { $0.1 < $1.1 }
		let visibleIntersection = bestScreenOverlap?.0.intersection(candidate) ?? .null
		let hasUsableVisibleArea = visibleIntersection.isNull == false
			&& visibleIntersection.width >= min(minimumVisibleSize.width, candidate.width)
			&& visibleIntersection.height >= min(minimumVisibleSize.height, candidate.height)
		let isUndersized = candidate.width < minimumSize.width || candidate.height < minimumSize.height

		guard frameIsFinite == false || isUndersized || hasUsableVisibleArea == false else {
			return frame
		}

		candidate.size.width = max(candidate.width, minimumSize.width)
		candidate.size.height = max(candidate.height, minimumSize.height)
		let targetScreen = if let bestScreenOverlap, bestScreenOverlap.1 > 0 {
			bestScreenOverlap.0
		} else {
			visibleScreenFrames.first
		}
		guard let targetScreen else {
			return candidate
		}

		candidate.size.width = min(candidate.width, targetScreen.width)
		candidate.size.height = min(candidate.height, targetScreen.height)

		if bestScreenOverlap?.1 ?? 0 > 0 {
			candidate.origin.x = min(max(candidate.minX, targetScreen.minX), targetScreen.maxX - candidate.width)
			candidate.origin.y = min(max(candidate.minY, targetScreen.minY), targetScreen.maxY - candidate.height)
		} else {
			candidate.origin.x = targetScreen.midX - candidate.width / 2
			candidate.origin.y = targetScreen.midY - candidate.height / 2
		}

		return candidate
	}

	private static func intersectionArea(of frame: CGRect, with screenFrame: CGRect) -> CGFloat {
		let intersection = frame.intersection(screenFrame)
		return intersection.isNull ? 0 : intersection.width * intersection.height
	}
}
