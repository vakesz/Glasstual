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

	override public convenience init() {
		self.init(port: 0)
	}

	public init(port: UInt16) {
		self.port = port
		super.init()
	}

	/// Isolated so it can release the mDNSResponder handle, which is only ever
	/// touched on the main actor.
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
		let status = DNSServiceNATPortMappingCreate(
			&newService,
			0,
			0,
			protocols,
			port.bigEndian,
			desiredPublicPort.bigEndian,
			0,
			portMapperCallback,
			Unmanaged.passUnretained(self).toOpaque()
		)
		guard status == kDNSServiceErr_NoError, let newService else {
			/* Report what mDNSResponder said: "NAT-PMP unsupported" and "bad
			 parameter" ask the caller for different things. */
			error = status == kDNSServiceErr_NoError ? Int32(kDNSServiceErr_Unknown) : status
			return false
		}
		service = newService
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

	fileprivate func update(error errorCode: DNSServiceErrorType, address: UInt32, port: UInt16) {
		var errorCode = errorCode
		if errorCode == 0, port == 0, desiredPublicPort > 0 {
			errorCode = Int32(kDNSServiceErr_NATPortMappingUnsupported)
		}
		error = errorCode
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

private let portMapperCallback: DNSServiceNATPortMappingReply =
	{ _, _, _, errorCode, publicAddress, _, _, publicPort, _, context in
		guard let context else { return }
		let mapper = Unmanaged<XRPortMapper>.fromOpaque(context).takeUnretainedValue()
		/* mDNSResponder delivers on the main queue, but the callback signature
		 carries no isolation, so hop rather than assume. */
		Task { @MainActor in
			mapper.update(error: errorCode, address: publicAddress, port: publicPort)
		}
	}
