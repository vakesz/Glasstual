// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
import os

/*  How the two ends of one transfer reach each other, and what happens once
 they have.

 A transfer that listens has to find a port, ask the router to forward it and
 work out which address to announce before it can be offered at all; one that
 dials has none of that to do. Either way the bytes themselves belong to a
 ``DCCTransfer`` actor, and what it reports is turned back here, on the main
 actor, into the status the row reads — so nothing it says crosses isolation
 twice. */

// MARK: - Listening, port mapping and this Mac's address

extension FileTransfer {
	func listeningServerDidStart(on port: UInt16) {
		guard transferStatus == .initializing else {
			assertionFailure("Listener started in an invalid transfer state")
			return
		}

		hostPort = port
		let mapper = PortMapper(port: port)
		mapper.mapTCP = true
		mapper.mapUDP = false
		mapper.desiredPublicPort = port
		negotiation.portMapping = mapper

		negotiation.portMapperNotifications.cancelAll()
		negotiation.portMapperNotifications.observe(.portMapperDidChange, object: mapper) { [weak self] notification in
			self?.portMapperDidFinishWork(notification)
		}
		transferStatus = .mappingListeningPort

		if !mapper.open() {
			portMapperDidFinishWork(nil)
		}
	}

	func noteIPAddressLookupSucceeded() {
		guard transferStatus.isAwaitingAddress else { return }
		if isSender {
			transferStatus = isReversed ? .waitingForReceiverToAccept : .isListeningAsSender
		} else if isReversed {
			transferStatus = .isListeningAsReceiver
		} else {
			return
		}
		sendTransferRequestToSession()
		guard isSender, isReversed else { return }

		/* A reverse offer the peer never answers leaves a listening port open and
		 a row that says it is waiting, with nothing left to wait for. */
		let run = negotiation.sessionID
		negotiation.offerTimeout?.cancel()
		negotiation.offerTimeout = Task { [weak self] in
			do { try await Task.sleep(for: FileTransferLimits.reverseOfferTimeout) } catch { return }
			guard let self, isCurrent(run), transferStatus == .waitingForReceiverToAccept else { return }
			close(with: .connectTimeout)
		}
	}

	func noteIPAddressLookupFailed() {
		guard transferStatus.isAwaitingAddress else { return }
		close(with: .sourceIPAddressUnknown)
	}

	/** `PortMapper` reports on every mDNSResponder callback, and a NAT-PMP
	 mapping is renewed for as long as it is held — so this fires again long
	 after the first result moved the transfer on. Only the first one has
	 anything to do. */
	private func portMapperDidFinishWork(_: Notification?) {
		guard transferStatus == .mappingListeningPort, let portMapping = negotiation.portMapping else { return }

		if portMapping.isMapped, portMapping.publicPort != 0 {
			/* The router picks the public port, and it need not be the one asked
			 for. The offer names it, and the peer's RESUME echoes it back, so it
			 is the port this transfer is known by from here on. */
			hostPort = portMapping.publicPort
			/* Bound to a local because the log message is an autoclosure, where
			 `self.` would be required and SwiftFormat would strip it. */
			let mappedPort = hostPort
			fileTransferLogger.info("Mapped DCC port \(mappedPort, privacy: .public)")
			updateIPAddress()
			return
		}

		fileTransferLogger.error(
			"DCC port mapping failed with code \(portMapping.error, privacy: .public)"
		)
		/* A listener can still be reachable directly or through a manually
		 forwarded port. That is equally true when a reverse-DCC receiver is
		 the listener, so a failed automatic mapping does not decide whether
		 either direction can continue. */
		updateIPAddress()
	}

	/** Works out the address the offer names, and moves the transfer on.

	 The transfer waits for it in `waitingForLocalIPAddress`, which is what the
	 center settles when the address is known, known to be unavailable, or
	 looked up — whichever comes first.

	 Reached from the negotiation as well as from a finished port mapping: a
	 reverse offer is announced by address alone, with no port to map first. */
	func updateIPAddress() {
		transferStatus = .waitingForLocalIPAddress
		/* A transfer whose list has gone has nobody left to work the address out
		 for it, which is the same position as there being no address to be had. */
		switch center?.resolveIPAddress(routerAddress: negotiation.portMapping?.publicAddress) {
		case .known:
			noteIPAddressLookupSucceeded()
		case .unavailable, .none:
			noteIPAddressLookupFailed()
		case .pending:
			break
		}
	}
}

// MARK: - Following the transfer actor

extension FileTransfer {
	/// Hands the transfer to a ``DCCTransfer`` actor and follows it.
	///
	/// Every event arrives back here on the main actor, which is where the
	/// status, the progress and the dialog all live, so nothing the actor
	/// reports has to cross isolation a second time.
	func startTransfer(with config: DCCTransfer.Config) {
		let transfer = DCCTransfer(config: config)
		negotiation.transfer = transfer

		let stopping = stopTask

		negotiation.transferEvents = Task { [weak self] in
			await stopping?.value
			guard Task.isCancelled == false else { await transfer.cancel(); return }
			await transfer.start()

			for await event in transfer.events {
				guard Task.isCancelled == false else { return }
				self?.transferDidReport(event, from: transfer)
			}
		}
	}

	/// Stops the running transfer, if there is one.
	func stopTransfer() {
		negotiation.sessionID = UUID()
		negotiation.transferEvents?.cancel()
		negotiation.transferEvents = nil

		guard let transfer = negotiation.transfer else {
			return
		}

		negotiation.transfer = nil
		enqueueStop { await transfer.cancel() }
	}

	func transferDidReport(_ event: DCCTransferEvent, from transfer: DCCTransfer) {
		guard negotiation.transfer === transfer else { return }
		switch event {
		case let .listening(port):
			listeningServerDidStart(on: port)
		case .connected:
			transferStatus = isSender ? .sending : .receiving
			center?.updateMaintenanceTimer()
		case let .progress(processedBytes):
			transferDidProgress(to: processedBytes)
		case let .completion(completion):
			self.completion = completion
		case .finished:
			transferStatus = .complete
			close()
		case let .failed(error):
			transferDidFail(with: error)
		}
	}

	private func transferDidProgress(to processedBytes: UInt64) {
		/* `currentRecord` is the byte count the maintenance timer turns into a
		 transfer rate once a second, so it takes the delta, not the total. */
		if processedBytes > processedFilesize {
			currentRecord += processedBytes - processedFilesize
		}

		processedFilesize = processedBytes
	}

	private func transferDidFail(with error: DCCTransferError) {
		guard transferStatus.isFinished == false else {
			return
		}

		fileTransferLogger.error("DCC transfer failed: \(String(describing: error), privacy: .public)")
		close(with: FileTransferFailure(error))
	}
}
