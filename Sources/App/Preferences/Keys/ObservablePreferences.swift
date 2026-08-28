/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
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

import Combine
import Foundation
import Observation
import SwiftUI

/** A main-actor observable face on the typed key store, for the SwiftUI sheets.

 The keys are values rather than properties of an object, so there is nothing
 for `@Observable` to track per setting. What is tracked instead is one
 revision counter that every read touches and every defaults change bumps: a
 view that reads any preference through this store is re-evaluated when any
 preference changes. That is coarse, and right for a settings sheet, where the
 alternative — 170 published properties — buys precision nothing needs. */
@MainActor
@Observable
public final class ObservablePreferences {
	public static let shared = ObservablePreferences()

	/// Touched by every read and bumped by every change. Private because it is
	/// the mechanism, not part of the interface.
	private var revision: UInt = 0

	@ObservationIgnored
	private var observation: AnyCancellable?

	private init() {
		observation = NotificationCenter.default.publisher(
			for: UserDefaults.didChangeNotification,
			object: TextualUserDefaults.shared()
		)
		.receive(on: DispatchQueue.main)
		.sink { [weak self] _ in
			/* ISOLATION-EXCEPTION: Combine's sink closure is nonisolated. The
			 publisher above delivers on the main queue. */
			MainActor.assumeIsolated {
				self?.revision &+= 1
			}
		}
	}

	public subscript<Value>(key: PreferenceKey<Value>) -> Value {
		get {
			_ = revision
			return key.value
		}
		set { key.value = newValue }
	}

	public func binding<Value>(for key: PreferenceKey<Value>) -> Binding<Value> {
		Binding(
			get: { self[key] },
			set: { self[key] = $0 }
		)
	}
}
