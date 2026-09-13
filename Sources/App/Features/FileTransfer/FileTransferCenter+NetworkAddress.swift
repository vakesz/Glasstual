/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2020 Codeux Software, LLC & respective contributors.
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

extension FileTransferCenter {
	/** The address this Mac's DCC offers name.

	 A manually entered address always wins; otherwise it is whatever the last
	 successful port mapping or address lookup reported. */
	var ipAddress: String? {
		get {
			if Preferences.FileTransfers.ipAddressDetectionMethod.value == .manual {
				let address = Preferences.FileTransfers.manuallyEnteredIPAddress.storedValue
				return address?.isEmpty == false ? address : nil
			}

			return cachedIPAddress
		}
		set { cachedIPAddress = newValue }
	}

	func clearIPAddress() {
		ipAddress = nil
		ipAddressLookup?.cancel()
		ipAddressLookup = nil
		for transfer in model.transfers where transfer.transferStatus == .waitingForLocalIPAddress {
			transfer.noteIPAddressLookupFailed()
		}
	}

	/** The address this Mac's DCC offers name, asking the address service for
	 it when it is not known yet.

	 The service is asked at most once at a time: two concurrent DCC offers
	 both reach this, and both have to be answered by the same lookup rather
	 than asking a public service twice for an answer that cannot have changed
	 in between.

	 `nil` when the user entered the address by hand or left it to the router,
	 because neither is an address this side can discover. */
	@discardableResult
	func lookUpIPAddress() async -> String? {
		if let ipAddress {
			return ipAddress
		}

		let method = Preferences.FileTransfers.ipAddressDetectionMethod.value

		guard method != .manual, method != .routerOnly else {
			return nil
		}

		if let running = ipAddressLookup {
			return await running.value
		}

		let lookup = Task { await InternetAddressLookup.address() }
		ipAddressLookup = lookup
		let address = await lookup.value

		/* A cancelled lookup was cancelled by `clearIPAddress()`, which has
		 already told the waiting transfers. */
		guard lookup.isCancelled == false else { return nil }

		ipAddressLookup = nil
		ipAddress = address
		for transfer in model.transfers where transfer.transferStatus == .waitingForLocalIPAddress {
			if address == nil {
				transfer.noteIPAddressLookupFailed()
			} else {
				transfer.noteIPAddressLookupSucceeded()
			}
		}

		return address
	}
}
