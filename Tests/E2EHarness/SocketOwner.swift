import Darwin
import Foundation

/** Which process holds the other end of a loopback connection.

 A loopback peer listens on a port the kernel picked, and anything on the
 machine can dial it. When a connection arrives that the fixture's own client
 did not make, its address says nothing: every loopback client is 127.0.0.1.
 The process that owns the socket is what tells a stray dial from another test
 run apart from the application opening a second connection.

 Only this user's processes are visible, and only while the socket is open. */
enum SocketOwner {
	struct Process: Equatable {
		let identifier: Int32
		let name: String
	}

	/// The process with a TCP socket bound to `localPort` and connected to
	/// `remotePort`, both on loopback.
	static func process(localPort: UInt16, remotePort: UInt16) -> Process? {
		for identifier in processIdentifiers() where holdsSocket(identifier, localPort: localPort, remotePort: remotePort) {
			var name = [CChar](repeating: 0, count: 256)
			proc_name(identifier, &name, UInt32(name.count))
			let bytes = name.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
			return Process(identifier: identifier, name: String(bytes: bytes, encoding: .utf8) ?? "")
		}
		return nil
	}

	private static func processIdentifiers() -> [Int32] {
		let count = proc_listallpids(nil, 0)
		guard count > 0 else { return [] }
		var identifiers = [Int32](repeating: 0, count: Int(count) + 64)
		let filled = proc_listallpids(&identifiers, Int32(identifiers.count * MemoryLayout<Int32>.stride))
		return filled > 0 ? Array(identifiers.prefix(Int(filled))).filter { $0 > 0 } : []
	}

	private static func holdsSocket(_ identifier: Int32, localPort: UInt16, remotePort: UInt16) -> Bool {
		let stride = MemoryLayout<proc_fdinfo>.stride
		let size = proc_pidinfo(identifier, PROC_PIDLISTFDS, 0, nil, 0)
		guard size > 0 else { return false }
		var descriptors = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(size) / stride + 16)
		let filled = proc_pidinfo(identifier, PROC_PIDLISTFDS, 0, &descriptors, Int32(descriptors.count * stride))
		guard filled > 0 else { return false }
		for descriptor in descriptors.prefix(Int(filled) / stride) where descriptor.proc_fdtype == PROX_FDTYPE_SOCKET {
			var socket = socket_fdinfo()
			let read = proc_pidfdinfo(
				identifier, descriptor.proc_fd, PROC_PIDFDSOCKETINFO, &socket, Int32(MemoryLayout<socket_fdinfo>.size)
			)
			guard read == Int32(MemoryLayout<socket_fdinfo>.size), socket.psi.soi_kind == SOCKINFO_TCP else { continue }
			let endpoints = socket.psi.soi_proto.pri_tcp.tcpsi_ini
			// The kernel reports both ports in network byte order.
			if UInt16(truncatingIfNeeded: endpoints.insi_lport).bigEndian == localPort,
			   UInt16(truncatingIfNeeded: endpoints.insi_fport).bigEndian == remotePort
			{
				return true
			}
		}
		return false
	}
}
