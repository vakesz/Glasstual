/*
 Disclaimer: IMPORTANT:  This Apple software is supplied to you by
 Apple Inc. ("Apple") in consideration of your agreement to the
 following terms, and your use, installation, modification or
 redistribution of this Apple software constitutes acceptance of these
 terms.  If you do not agree with these terms, please do not use,
 install, modify or redistribute this Apple software.

 In consideration of your agreement to abide by the following terms, and
 subject to these terms, Apple grants you a personal, non-exclusive
 license, under Apple's copyrights in this original Apple software, to
 use, reproduce, modify and redistribute the Apple Software, with or
 without modifications, in source and/or binary forms; provided that if
 you redistribute the Apple Software in its entirety and without
 modifications, you must retain this notice and the following text and
 disclaimers in all such redistributions of the Apple Software. Neither
 the name, trademarks, service marks or logos of Apple Inc. may be used to
 endorse or promote products derived from the Apple Software without
 specific prior written permission from Apple. Except as expressly stated
 in this notice, no other rights or licenses, express or implied, are
 granted by Apple herein, including but not limited to any patent rights
 that may be infringed by your derivative works or by other works in which
 the Apple Software may be incorporated.

 The Apple Software is provided by Apple on an "AS IS" basis. APPLE MAKES
 NO WARRANTIES, EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION THE
 IMPLIED WARRANTIES OF NON-INFRINGEMENT, MERCHANTABILITY AND FITNESS FOR A
 PARTICULAR PURPOSE, REGARDING THE APPLE SOFTWARE OR ITS USE AND OPERATION
 ALONE OR IN COMBINATION WITH YOUR PRODUCTS.

 IN NO EVENT SHALL APPLE BE LIABLE FOR ANY SPECIAL, INDIRECT, INCIDENTAL OR
 CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 INTERRUPTION) ARISING IN ANY WAY OUT OF THE USE, REPRODUCTION,
 MODIFICATION AND/OR DISTRIBUTION OF THE APPLE SOFTWARE, HOWEVER CAUSED AND
 WHETHER UNDER THEORY OF CONTRACT, TORT (INCLUDING NEGLIGENCE), STRICT
 LIABILITY OR OTHERWISE, EVEN IF APPLE HAS BEEN ADVISED OF THE POSSIBILITY
 OF SUCH DAMAGE.

 Copyright © 2007 Apple Inc. All Rights Reserved.
 */

import Darwin
import dnssd
import Foundation

public extension Notification.Name {
	/// Posted by the `XRPortMapper` whose mapping changed. Both observers are in
	/// process, so the raw string crosses no boundary and is not persisted.
	static let portMapperDidChange = Notification.Name("com.vakesz.glasstual.portMapperDidChange")
}

/// A NAT-PMP port mapping for one local port.
///
/// Main actor throughout: every caller is a DCC transfer or dialog that already
/// runs there, and the mDNSResponder callback is delivered on the main queue.
@MainActor
public final class XRPortMapper: NSObject {
	public var mapTCP = true
	public var mapUDP = false
	public var desiredPublicPort: UInt16 = 0
	public private(set) var error: Int32 = 0
	public private(set) var publicAddress: String?
	public private(set) var publicPort: UInt16 = 0

	private let port: UInt16
	private var rawPublicAddress: UInt32 = 0
	private var service: DNSServiceRef?
	/// The `+1` handed to mDNSResponder as the callback context, released in
	/// `disconnect()`. It is a box that names the mapper weakly, not the mapper
	/// itself: see ``XRPortMapperCallbackBox``.
	private var callbackContext: UnsafeMutableRawPointer?
	/// Which mapping is open, counting up from the first. A reply carries the
	/// number of the mapping it belongs to, which is what tells a reply for the
	/// mapping being held apart from one for a mapping that has been closed or
	/// reopened since. A `DNSServiceRef` could not: it is a pointer, and the
	/// allocator is free to hand the next mapping the address the last one had.
	private var mappingGeneration: UInt64 = 0

	override public convenience init() {
		self.init(port: 0)
	}

	public init(port: UInt16) {
		self.port = port
		super.init()
	}

	/// Closes a mapping whose owner simply let go of it. Isolated so it can
	/// release the mDNSResponder handle, which is only ever touched on the main
	/// actor.
	isolated deinit {
		disconnect()
	}

	public var isMapped: Bool {
		rawPublicAddress != 0 && rawPublicAddress != Self.rawLocalAddress
	}

	public func open() -> Bool {
		precondition(service == nil, "Port mapping already in progress")
		var protocols = DNSServiceProtocol(0)
		if mapTCP {
			protocols |= DNSServiceProtocol(kDNSServiceProtocol_TCP)
		}
		if mapUDP {
			protocols |= DNSServiceProtocol(kDNSServiceProtocol_UDP)
		}
		var newService: DNSServiceRef?
		mappingGeneration &+= 1
		/* The context is a raw pointer a C API keeps for as long as the service
		 lives, so what it names is retained for exactly that long and released
		 in `disconnect()`. What is retained is a box that names the mapper
		 weakly: retaining the mapper itself made an open mapping keep its own
		 owner alive, which put `deinit` — and the `disconnect()` it runs —
		 beyond reach for anything but an explicit `close()`. An unretained
		 pointer is not the answer either: it was only sound while nothing
		 released the mapper between the callback firing and the hop to the main
		 actor, which is a guarantee no caller was told about. */
		let context = Unmanaged.passRetained(
			XRPortMapperCallbackBox(mapper: self, generation: mappingGeneration)
		).toOpaque()
		let status = DNSServiceNATPortMappingCreate(
			&newService,
			0,
			0,
			protocols,
			port.bigEndian,
			desiredPublicPort.bigEndian,
			0,
			portMapperCallback,
			context
		)
		guard status == kDNSServiceErr_NoError, let newService else {
			Unmanaged<XRPortMapperCallbackBox>.fromOpaque(context).release()
			/* Report what mDNSResponder said: "NAT-PMP unsupported" and "bad
			 parameter" ask the caller for different things. */
			error = status == kDNSServiceErr_NoError ? Int32(kDNSServiceErr_Unknown) : status
			return false
		}
		service = newService
		callbackContext = context
		let dispatchStatus = DNSServiceSetDispatchQueue(newService, .main)
		guard dispatchStatus == kDNSServiceErr_NoError else {
			disconnect()
			error = dispatchStatus
			return false
		}
		return true
	}

	public func close() {
		disconnect()
		error = 0
	}

	public nonisolated static var localAddress: String? { // nonisolated: pure
		string(from: rawLocalAddress)
	}

	public nonisolated static var localAddressIsPrivate: Bool { // nonisolated: pure
		let address = UInt32(bigEndian: rawLocalAddress)
		let ranges: [(UInt32, UInt32)] = [
			(0xFF00_0000, 0x0000_0000), (0xFF00_0000, 0x0A00_0000),
			(0xFF00_0000, 0x7F00_0000), (0xFFFF_0000, 0xA9FE_0000),
			(0xFFF0_0000, 0xAC10_0000), (0xFFFF_0000, 0xC0A8_0000),
		]
		return ranges.contains { address & $0.0 == $0.1 }
	}

	/** What one mDNSResponder reply means for the mapping.

	 A reply that reports success and a public port of zero is the router saying
	 it mapped nothing, whatever port was asked for. Reading it as success left
	 a transfer advertising port zero to its peer, and the condition used to
	 depend on `desiredPublicPort` — so a mapper that let the router choose the
	 port took the refusal for a mapping. */
	public nonisolated static func resolvedError( // nonisolated: pure
		reportedError: DNSServiceErrorType,
		publicPort: UInt16
	) -> DNSServiceErrorType {
		guard reportedError == 0, publicPort == 0 else {
			return reportedError
		}

		return DNSServiceErrorType(kDNSServiceErr_NATPortMappingUnsupported)
	}

	/** Records one reply, from the mapping numbered `replyingGeneration`.

	 mDNSResponder answers on the main queue, but a C callback carries no
	 isolation and reaching the main actor from one costs a hop. A `close()` can
	 land inside that hop, and the update that arrived afterwards put back the
	 address and port `close()` had just cleared — so a transfer whose mapping
	 had been released went on advertising it. Comparing the mapping the reply
	 belongs to against the one being held rejects both that and a reply
	 belonging to a mapping that has since been reopened. */
	fileprivate func update(
		fromGeneration replyingGeneration: UInt64,
		error errorCode: DNSServiceErrorType,
		address: UInt32,
		port: UInt16
	) {
		guard service != nil, replyingGeneration == mappingGeneration else { return }

		error = Self.resolvedError(reportedError: errorCode, publicPort: port)
		rawPublicAddress = address
		publicAddress = Self.string(from: address)
		publicPort = UInt16(bigEndian: port)
		NotificationCenter.default.post(name: .portMapperDidChange, object: self)
	}

	private func disconnect() {
		guard let service else { return }
		DNSServiceRefDeallocate(service)
		self.service = nil
		rawPublicAddress = 0
		publicAddress = nil
		publicPort = 0
		/* Deallocating the service is what ends the callback's claim on the
		 context, and the same call is what stops further callbacks — both on
		 this queue, so nothing is in flight to be released out from under. */
		if let callbackContext {
			self.callbackContext = nil
			Unmanaged<XRPortMapperCallbackBox>.fromOpaque(callbackContext).release()
		}
	}

	private nonisolated static var rawLocalAddress: UInt32 { // nonisolated: pure
		var interfaces: UnsafeMutablePointer<ifaddrs>?
		guard getifaddrs(&interfaces) == 0 else { return 0 }
		defer { freeifaddrs(interfaces) }
		var current = interfaces
		while let interface = current?.pointee {
			defer { current = interface.ifa_next }
			guard interface.ifa_flags & UInt32(IFF_UP) != 0,
			      interface.ifa_flags & UInt32(IFF_LOOPBACK) == 0,
			      let address = interface.ifa_addr,
			      address.pointee.sa_family == UInt8(AF_INET)
			else { continue }
			return UnsafeRawPointer(address).assumingMemoryBound(to: sockaddr_in.self).pointee.sin_addr.s_addr
		}
		return 0
	}

	private nonisolated static func string(from address: UInt32) -> String? { // nonisolated: pure
		guard address != 0 else { return nil }
		var address = in_addr(s_addr: address)
		var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
		guard inet_ntop(AF_INET, &address, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil else { return nil }
		let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
		return String(bytes: bytes, encoding: .utf8)
	}
}

/** What mDNSResponder is handed as the callback context for one mapping.

 The service holds a `+1` on this, and `disconnect()` releases it. The mapper is
 named weakly so that an open mapping does not keep its own owner alive: the
 mapper's `deinit` is what closes a mapping nobody closed explicitly, and it
 cannot run while the service is holding a reference to it.

 Main actor because the mapper it names is, and the weak reference is read there.
 A reply arrives on the main queue but carries no isolation, so it hops; the
 callback itself only takes the box unretained and hands it to that hop. */
@MainActor
private final class XRPortMapperCallbackBox {
	weak var mapper: XRPortMapper?
	/// Which mapping this box was made for. A reply for an earlier one is
	/// rejected even though the box is only ever used by one.
	let generation: UInt64

	init(mapper: XRPortMapper, generation: UInt64) {
		self.mapper = mapper
		self.generation = generation
	}
}

private let portMapperCallback: DNSServiceNATPortMappingReply =
	{ _, _, _, errorCode, publicAddress, _, _, publicPort, _, context in
		guard let context else { return }
		/* Unretained: the `+1` belongs to the service, not to one reply, and a
		 retained take here would release it on the first callback of a mapping
		 that goes on reporting for as long as it is renewed. The box outlives
		 the hop below because the hop holds a reference of its own. */
		let box = Unmanaged<XRPortMapperCallbackBox>.fromOpaque(context).takeUnretainedValue()
		/* mDNSResponder delivers on the main queue, but the callback signature
		 carries no isolation, so hop rather than assume. `update` re-checks that
		 the reply still belongs to the mapping being held, because a close can
		 land inside the hop. */
		Task { @MainActor in
			box.mapper?.update(
				fromGeneration: box.generation,
				error: errorCode,
				address: publicAddress,
				port: publicPort
			)
		}
	}
