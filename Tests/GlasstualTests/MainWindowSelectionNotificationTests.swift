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

import Foundation
@testable import Glasstual
import Testing

/** The selection notification had four declarations and one bare string
 literal. Four of them agreed, which is exactly why nobody noticed: an observer
 that watched a fifth, mistyped name would simply never fire. One declaration
 now carries the name, and this pins what it posts under. */
@MainActor
struct MainWindowSelectionNotificationTests {
	private static let postedName = "TVCMainWindowSelectionChangedNotification"

	@Test("The selection notification keeps the name every observer registered under")
	func selectionNotificationKeepsItsPostedName() {
		#expect(Notification.Name.mainWindowSelectionChanged.rawValue == Self.postedName)
	}

	/// An observer registered the old way — with the raw string the deleted
	/// declarations spelled out — still hears what the constant posts.
	@Test("Posting the constant reaches an observer registered under the raw name")
	func postingTheConstantReachesTheRawName() async {
		let center = NotificationCenter.default
		let received = await confirmation("selection notification observed") { confirm in
			let token = center.addObserver(
				forName: Notification.Name(Self.postedName),
				object: nil,
				queue: nil
			) { _ in
				confirm()
			}

			center.post(name: .mainWindowSelectionChanged, object: nil)
			center.removeObserver(token)

			return true
		}

		#expect(received)
	}
}
