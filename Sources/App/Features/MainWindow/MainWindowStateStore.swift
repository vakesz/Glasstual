/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import CocoaExtensions
import CoreGraphics
import Foundation

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

struct MainWindowLayoutState: Equatable, Sendable {
	var isServerListVisible: Bool
	var isMemberListVisible: Bool
}

struct MainWindowStateStore {
	private let defaults: UserDefaults

	/// Window restoration stays in the group container so every process-local
	/// app launch sees one state. It is deliberately excluded from settings
	/// import and export by the typed key declarations.
	init(defaults: UserDefaults = TextualUserDefaults.container) {
		self.defaults = defaults
	}

	func saveLayout(_ state: MainWindowLayoutState) {
		defaults[Preferences.MainWindow.serverListVisible] = state.isServerListVisible
		defaults[Preferences.MainWindow.memberListVisible] = state.isMemberListVisible
	}

	func loadLayout() -> MainWindowLayoutState {
		MainWindowLayoutState(
			isServerListVisible: defaults[Preferences.MainWindow.serverListVisible],
			isMemberListVisible: defaults[Preferences.MainWindow.memberListVisible]
		)
	}

	func saveTextSizeMultiplier(_ multiplier: Double) {
		defaults[Preferences.MainWindow.textSizeMultiplier] = multiplier
	}

	/// The stored transcript zoom, or the declared default when what is stored
	/// is not a zoom the window is willing to apply.
	func loadTextSizeMultiplier() -> Double {
		let key = Preferences.MainWindow.textSizeMultiplier
		guard let stored = defaults[stored: key],
		      key.accepts(stored)
		else {
			return key.defaultValue
		}

		return stored
	}

	func saveSelection(itemIdentifier: String?) {
		guard let itemIdentifier, itemIdentifier.isEmpty == false else {
			defaults.removeValue(for: Preferences.MainWindow.serverListSelection)
			return
		}
		defaults.setPropertyListValue(.string(itemIdentifier), for: Preferences.MainWindow.serverListSelection)
	}

	func loadSelectionItemIdentifier() -> String? {
		let key = Preferences.MainWindow.serverListSelection
		let stored = defaults.propertyListValue(for: key)
		if let identifier = stored?.string, !identifier.isEmpty {
			return identifier
		}
		guard let identifier = stored?.stringArray?.last,
		      !identifier.isEmpty
		else {
			return nil
		}
		defaults.setPropertyListValue(.string(identifier), for: key)
		return identifier
	}
}
