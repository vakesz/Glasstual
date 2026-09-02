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
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 *  * Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *  * Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *  * Neither the name of Textual, "Codeux Software, LLC", nor the
 *    names of its contributors may be used to endorse or promote products
 *    derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 *********************************************************************** */

import AppKit
@testable import Glasstual
import SwiftUI
import Testing

/** What `applicationShouldTerminate` does with a quit request.

 `terminateGracefully()` — the power-off path — used to raise
 `applicationIsTerminating` itself, which made the delegate read termination as
 already under way and answer without running step one. Nothing left IRC
 gracefully and no historic log was saved. Skipping the confirmation is all
 that path is entitled to. */
struct ApplicationTerminationPolicyTests {
	@Test("The power-off path skips the question, not the termination steps")
	func skippingConfirmationStillBegins() {
		#expect(
			ApplicationTerminationPolicy.decision(
				isTerminating: false,
				isAwaitingConfirmation: false,
				skipConfirmation: true,
				confirmQuitPreference: true,
				hasLiveConnection: true
			) == .begin
		)
	}

	@Test("A live connection is confirmed before quitting")
	func aLiveConnectionIsConfirmed() {
		#expect(
			ApplicationTerminationPolicy.decision(
				isTerminating: false,
				isAwaitingConfirmation: false,
				skipConfirmation: false,
				confirmQuitPreference: true,
				hasLiveConnection: true
			) == .confirm
		)
	}

	@Test("Nothing is asked with the preference off, or with nothing connected")
	func nothingToConfirm() {
		#expect(
			ApplicationTerminationPolicy.decision(
				isTerminating: false,
				isAwaitingConfirmation: false,
				skipConfirmation: false,
				confirmQuitPreference: false,
				hasLiveConnection: true
			) == .begin
		)
		#expect(
			ApplicationTerminationPolicy.decision(
				isTerminating: false,
				isAwaitingConfirmation: false,
				skipConfirmation: false,
				confirmQuitPreference: true,
				hasLiveConnection: false
			) == .begin
		)
	}

	/// Answering `.terminateNow` on a second request used to schedule step one
	/// again, tearing everything down twice.
	@Test("A shutdown already in flight is left alone")
	func terminationInFlightIsLeftAlone() {
		#expect(
			ApplicationTerminationPolicy.decision(
				isTerminating: true,
				isAwaitingConfirmation: false,
				skipConfirmation: true,
				confirmQuitPreference: false,
				hasLiveConnection: false
			) == .alreadyTerminating
		)
	}

	/// Sheets stack, so a second ⌘Q while the confirmation is up used to queue a
	/// second sheet: answering quit on one and cancel on the other replied
	/// `false` to a shutdown already in flight.
	@Test("A confirmation already on screen answers for later requests too")
	func aPendingConfirmationIsNotAskedTwice() {
		#expect(
			ApplicationTerminationPolicy.decision(
				isTerminating: false,
				isAwaitingConfirmation: true,
				skipConfirmation: false,
				confirmQuitPreference: true,
				hasLiveConnection: true
			) == .alreadyDeciding
		)
	}

	@Test("A shutdown in flight outranks a confirmation still on screen")
	func terminationOutranksAPendingConfirmation() {
		#expect(
			ApplicationTerminationPolicy.decision(
				isTerminating: true,
				isAwaitingConfirmation: true,
				skipConfirmation: false,
				confirmQuitPreference: true,
				hasLiveConnection: true
			) == .alreadyTerminating
		)
	}
}

/// One drawing strategy for the dock badge: the badge view draws both counts,
/// and the system badge label is never used. Falling back to the label whenever
/// the highlight count was zero made the icon change shape depending on whether
/// anyone had said your name.
@MainActor
struct DockIconBadgeStrategyTests {
	private func draw(highlights: UInt, messages: UInt) {
		DockIcon.resetCachedCount()
		DockIcon.draw(withHighlightCount: highlights, messageCount: messages)
	}

	@Test("A message count with no highlights is drawn by the badge view")
	func messagesAloneUseTheBadgeView() {
		draw(highlights: 0, messages: 5)

		let dockTile = NSApp.dockTile

		#expect(dockTile.contentView is DockIconBadgeHostingView)
		#expect(dockTile.badgeLabel == nil)
		#expect((dockTile.contentView as? DockIconBadgeHostingView)?.rootView.messageCount == 5)
	}

	@Test("Highlights and messages share the one badge view")
	func highlightsAndMessagesShareTheView() {
		draw(highlights: 2, messages: 5)

		let badgeView = NSApp.dockTile.contentView as? DockIconBadgeHostingView

		#expect(badgeView?.rootView.highlightCount == 2)
		#expect(badgeView?.rootView.messageCount == 5)
		#expect(NSApp.dockTile.badgeLabel == nil)
	}

	@Test("With nothing to report the icon carries no badge at all")
	func zeroCountsClearTheTile() {
		draw(highlights: 1, messages: 1)
		draw(highlights: 0, messages: 0)

		#expect(NSApp.dockTile.contentView == nil)
		#expect(NSApp.dockTile.badgeLabel == nil)
	}

	/// Unticking the preference used to return before clearing, leaving the
	/// badge on the dock until the next relaunch.
	@Test("Turning the preference off clears a badge already drawn")
	func disablingThePreferenceClearsTheTile() {
		let key = Preferences.Notifications.displayDockBadge
		let original = key.value
		defer { key.value = original }

		draw(highlights: 1, messages: 1)

		key.value = false
		DockIcon.updateDockIcon()

		#expect(NSApp.dockTile.contentView == nil)
		#expect(NSApp.dockTile.badgeLabel == nil)
	}
}
