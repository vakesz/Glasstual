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

import CocoaExtensions
import Foundation
import Network

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

	/** Forgets the address, because what it would be may have changed.

	 A transfer already waiting for one is not failed for it: the address is
	 worked out again under whatever the settings now say, and the transfer is
	 settled by that answer. Failing it left a download the user had accepted
	 broken by nothing more than a preference being touched. */
	func clearIPAddress() {
		cachedIPAddress = nil
		ipAddressLookup?.cancel()
		ipAddressLookup = nil

		guard model.transfers.contains(where: { $0.transferStatus == .waitingForLocalIPAddress }) else {
			return
		}

		_ = resolveIPAddress(routerAddress: nil)
	}

	/** The address this Mac's DCC offers name, asking the address service for
	 it when it is not known yet.

	 `routerAddress` is the public address a port mapping reported, which is
	 used — and remembered — when nothing better is known.

	 The service is asked at most once at a time: two concurrent DCC offers
	 both reach this, and both have to be answered by the same lookup rather
	 than asking a public service twice for an answer that cannot have changed
	 in between.

	 `nil` when there is no address to be had: the user chose to enter one by
	 hand and has not, or left it to a router that did not map the port. */
	@discardableResult
	func lookUpIPAddress(routerAddress: String? = nil) async -> String? {
		switch resolveIPAddress(routerAddress: routerAddress) {
		case let .known(address):
			address
		case .unavailable:
			nil
		case let .pending(lookup):
			await lookup.value
		}
	}

	/// What working out the address came to, without waiting for it.
	enum IPAddressResolution {
		case known(String)
		case unavailable
		case pending(Task<String?, Never>)
	}

	/// Settles the transfers waiting for an address with what is already known,
	/// or starts the one lookup that will settle them.
	func resolveIPAddress(routerAddress: String?) -> IPAddressResolution {
		let method = Preferences.FileTransfers.ipAddressDetectionMethod.value

		if let address = ipAddress ?? acceptedRouterAddress(routerAddress, method: method) {
			settleTransfersWaitingForAddress(with: address)
			return .known(address)
		}

		guard method != .manual, method != .routerOnly else {
			settleTransfersWaitingForAddress(with: nil)
			return .unavailable
		}

		if let running = ipAddressLookup {
			return .pending(running)
		}

		let lookup = Task { [weak self, addressSource] () -> String? in
			let address = await addressSource()

			/* A cancelled lookup was abandoned by `clearIPAddress()`, which has
			 already started whatever replaces it. */
			guard Task.isCancelled == false, let self else { return nil }

			ipAddressLookup = nil
			cachedIPAddress = address
			settleTransfersWaitingForAddress(with: address)
			return address
		}
		ipAddressLookup = lookup
		return .pending(lookup)
	}

	private func acceptedRouterAddress(_ routerAddress: String?, method: FileTransferIPAddressSource) -> String? {
		guard method != .manual, let routerAddress, routerAddress.isIPAddress else { return nil }
		cachedIPAddress = routerAddress
		return routerAddress
	}

	private func settleTransfersWaitingForAddress(with address: String?) {
		for transfer in model.transfers where transfer.transferStatus == .waitingForLocalIPAddress {
			if address == nil {
				transfer.noteIPAddressLookupFailed()
			} else {
				transfer.noteIPAddressLookupSucceeded()
			}
		}
	}

	// MARK: - Following the network

	/// The parts of a network path that decide what this Mac looks like from
	/// the internet.
	struct NetworkPathSignature: Equatable {
		var isSatisfied: Bool
		var interfaces: [String]
		var gateways: [NWEndpoint]

		init(_ path: NWPath) {
			isSatisfied = path.status == .satisfied
			interfaces = path.availableInterfaces.map(\.name)
			gateways = path.gateways
		}

		init(isSatisfied: Bool, interfaces: [String], gateways: [NWEndpoint]) {
			self.isSatisfied = isSatisfied
			self.interfaces = interfaces
			self.gateways = gateways
		}
	}

	/** Forgets the address whenever the network this Mac is on changes.

	 The address was cached for the life of the process, so a laptop that moved
	 from home to a café went on offering transfers from its home address. The
	 monitor's first report is the network as it already was, and moves nothing. */
	func followNetworkChanges() -> Task<Void, Never> {
		Task { [weak self] in
			var previous: NetworkPathSignature?
			for await path in NWPathMonitor() {
				let signature = NetworkPathSignature(path)
				defer { previous = signature }
				guard let previous, previous != signature, let self else { continue }
				networkPathDidChange()
			}
		}
	}

	func networkPathDidChange() {
		guard cachedIPAddress != nil || ipAddressLookup != nil else { return }
		clearIPAddress()
	}
}
