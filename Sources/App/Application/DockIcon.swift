/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit
import SwiftUI

public enum DockIcon {
	private static let maximumDisplayedCount: UInt = 9999

	@MainActor private static var cachedHighlightCount = -1
	@MainActor private static var cachedMessageCount = -1

	@MainActor public static func updateDockIcon() {
		/* Turning the preference off has to clear whatever is already drawn:
		 this is the only thing the preference-change path calls. */
		guard Preferences.Notifications.displayDockBadge.value else {
			drawWithoutCount()
			return
		}

		guard let world = AppController.shared.world else { return }

		var highlightCount: UInt = 0
		var messageCount: UInt = 0
		for client in world.clientList {
			for channel in client.channelList {
				if channel.config.pushNotifications {
					messageCount += UInt(channel.dockUnreadCount)
				}
				highlightCount += UInt(channel.nicknameHighlightCount)
			}
		}

		if messageCount == 0, highlightCount == 0 {
			drawWithoutCount()
		} else {
			draw(withHighlightCount: highlightCount, messageCount: messageCount)
		}
	}

	@MainActor public static func resetCachedCount() {
		cachedMessageCount = -1
		cachedHighlightCount = -1
	}

	@MainActor public static func drawWithoutCount() {
		guard cachedHighlightCount != 0 || cachedMessageCount != 0 else { return }
		cachedMessageCount = 0
		cachedHighlightCount = 0

		let dockTile = NSApp.dockTile
		dockTile.badgeLabel = nil
		dockTile.contentView = nil
		dockTile.display()
	}

	@MainActor public static func draw(withHighlightCount highlightCount: UInt, messageCount: UInt) {
		guard cachedHighlightCount != Int(highlightCount) || cachedMessageCount != Int(messageCount) else {
			return
		}

		cachedHighlightCount = Int(highlightCount)
		cachedMessageCount = Int(messageCount)

		guard highlightCount > 0 || messageCount > 0 else {
			let dockTile = NSApp.dockTile
			dockTile.badgeLabel = nil
			dockTile.contentView = nil
			dockTile.display()
			return
		}

		let dockTile = NSApp.dockTile
		dockTile.badgeLabel = nil
		let badgeView = dockTile.contentView as? DockIconBadgeHostingView ?? {
			let view = DockIconBadgeHostingView(
				rootView: DockIconBadgeContent(highlightCount: 0, messageCount: 0)
			)
			view.frame = NSRect(origin: .zero, size: dockTile.size)
			dockTile.contentView = view
			return view
		}()

		badgeView.rootView = DockIconBadgeContent(
			highlightCount: highlightCount,
			messageCount: messageCount
		)
		dockTile.display()
	}

	public static func badgeString(forCount count: UInt) -> String {
		if count > maximumDisplayedCount {
			return MainWindowStrings.Dock.overflowBadge(
				maximum: formattedNumber(Int(maximumDisplayedCount)) as String
			)
		}
		return formattedNumber(Int(count)) as String
	}
}

typealias DockIconBadgeHostingView = NSHostingView<DockIconBadgeContent>

struct DockIconBadgeContent: View {
	private enum Layout {
		static let stackSpacing: CGFloat = 1
		static let topPadding: CGFloat = 1
		static let badgeHeightRatio: CGFloat = 0.26
		static let fontSizeRatio: CGFloat = 0.62
		static let horizontalPaddingRatio: CGFloat = 0.3
		static let outlineOpacity: Double = 0.9
		static let outlineWidthRatio: CGFloat = 0.06
	}

	let highlightCount: UInt
	let messageCount: UInt

	var body: some View {
		GeometryReader { geometry in
			ZStack(alignment: .topTrailing) {
				if let icon = NSApp.applicationIconImage {
					Image(nsImage: icon)
						.resizable()
						.scaledToFit()
				}

				VStack(alignment: .trailing, spacing: Layout.stackSpacing) {
					if highlightCount > 0 {
						badge(highlightCount, color: .green, height: geometry.size.height * Layout.badgeHeightRatio)
					}
					if messageCount > 0 {
						badge(messageCount, color: .red, height: geometry.size.height * Layout.badgeHeightRatio)
					}
				}
				.padding(.top, Layout.topPadding)
			}
		}
	}

	private func badge(_ count: UInt, color: Color, height: CGFloat) -> some View {
		Text(DockIcon.badgeString(forCount: count))
			.font(.system(size: height * Layout.fontSizeRatio, weight: .bold))
			.foregroundStyle(.white)
			.padding(.horizontal, height * Layout.horizontalPaddingRatio)
			.frame(minWidth: height, minHeight: height)
			.background(color, in: Capsule())
			.overlay(
				Capsule().stroke(
					.white.opacity(Layout.outlineOpacity),
					lineWidth: max(1, height * Layout.outlineWidthRatio)
				)
			)
	}
}
