/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\\___/_/\\_\\__|\\__,_|\\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import AppKit

/** A reference box for one row of the server-endpoint table.

 `Server` is a value type, but the table's cell views edit their row through
 KVC — the nib binds each control to a property on the cell view, which reads
 and writes `objectValue`. A value in the array controller would hand every
 cell its own copy, so the row is boxed here and the box is what the controller
 arranges. The mirrored properties are `@objc dynamic` because the port cell
 observes the port that the TLS checkbox in a different cell changes. */
@objc(TDCServerEndpointListEntry)
@MainActor
public final class ServerEndpointListEntry: NSObject {
	public var server: Server

	public init(server: Server) {
		self.server = server
		super.init()
	}

	@objc public dynamic var serverAddress: String {
		get { server.serverAddress }
		set { server.serverAddress = newValue }
	}

	@objc public dynamic var serverPort: UInt16 {
		get { server.serverPort }
		set { server.serverPort = newValue }
	}

	@objc public dynamic var prefersSecuredConnection: Bool {
		get { server.prefersSecuredConnection }
		set { server.prefersSecuredConnection = newValue }
	}

	public var serverPassword: String? {
		get { server.serverPassword }
		set { server.serverPassword = newValue }
	}
}

@objc(TDCServerEndpointListSheetTableCellView)
public final class ServerEndpointListSheetTableCellView: NSTableCellView {
	@objc dynamic var serverAddress: String {
		get {
			guard let objectValue = objectValue as? ServerEndpointListEntry else {
				return ""
			}

			return objectValue.serverAddress
		}
		set {
			guard let objectValue = objectValue as? ServerEndpointListEntry else {
				return
			}

			objectValue.serverAddress = newValue
		}
	}

	@objc dynamic var serverPort: String {
		get {
			guard let objectValue = objectValue as? ServerEndpointListEntry else {
				return ""
			}

			return String(objectValue.serverPort)
		}
		set {
			guard let objectValue = objectValue as? ServerEndpointListEntry else {
				return
			}

			objectValue.serverPort = UInt16(Int(newValue) ?? 0)
		}
	}

	@objc dynamic var prefersSecuredConnection: NSNumber {
		get {
			guard let objectValue = objectValue as? ServerEndpointListEntry else {
				return NSNumber(value: NSControl.StateValue.off.rawValue)
			}

			return NSNumber(
				value: objectValue.prefersSecuredConnection
					? NSControl.StateValue.on.rawValue
					: NSControl.StateValue.off.rawValue
			)
		}
		set {
			guard let objectValue = objectValue as? ServerEndpointListEntry else {
				return
			}

			let prefersSecuredConnection =
				newValue.uintValue == NSControl.StateValue.on.rawValue

			if prefersSecuredConnection {
				objectValue.prefersSecuredConnection = true

				if objectValue.serverPort == 6667 {
					objectValue.serverPort = 6697
				}
			} else {
				objectValue.prefersSecuredConnection = false

				if objectValue.serverPort == 6697 {
					objectValue.serverPort = 6667
				}
			}
		}
	}

	@objc dynamic var serverPassword: String {
		get {
			guard let objectValue = objectValue as? ServerEndpointListEntry else {
				return ""
			}

			return objectValue.serverPassword ?? ""
		}
		set {
			guard let objectValue = objectValue as? ServerEndpointListEntry else {
				return
			}

			objectValue.serverPassword = newValue
		}
	}

	private var serverPortObservation: NSKeyValueObservation?

	override public nonisolated func validateValue(
		_ ioValue: AutoreleasingUnsafeMutablePointer<AnyObject?>,
		forKey inKey: String
	)
		throws
	{
		if inKey == "serverAddress" {
			let address = (ioValue.pointee as? String) ?? (ioValue.pointee as? NSString as String?) ?? ""

			if (address as NSString).isValidInternetAddress == false {
				throw NSError(
					domain: "GlasstualErrorDomain",
					code: 71013,
					userInfo: [
						NSLocalizedDescriptionKey: ServerEndpointStrings.invalidAddressDescription,
						NSLocalizedRecoverySuggestionErrorKey: ServerEndpointStrings.invalidAddressRecoverySuggestion,
					]
				)
			}
		} else if inKey == "serverPort" {
			let port = (ioValue.pointee as? String) ?? (ioValue.pointee as? NSString as String?) ?? ""

			if (port as NSString).isValidInternetPort == false {
				throw NSError(
					domain: "GlasstualErrorDomain",
					code: 71014,
					userInfo: [
						NSLocalizedDescriptionKey: ServerEndpointStrings.invalidPortDescription,
						NSLocalizedRecoverySuggestionErrorKey: ServerEndpointStrings.invalidPortRecoverySuggestion,
					]
				)
			}
		}
	}

	override public var objectValue: Any? {
		didSet {
			stopObservingObjectValue()
			startObservingObjectValue()
		}
	}

	private func startObservingObjectValue() {
		guard let keyPath = identifier?.rawValue else {
			return
		}

		willChangeValue(forKey: keyPath)
		didChangeValue(forKey: keyPath)

		guard keyPath == "serverPort", let objectValue = objectValue as? ServerEndpointListEntry else {
			return
		}

		serverPortObservation = objectValue.observe(\.serverPort, options: .new) { [weak self] _, _ in
			/* ISOLATION-EXCEPTION: `NSKeyValueObservation`'s change handler is
			 nonisolated. AppKit posts these changes on the main thread. */
			MainActor.assumeIsolated {
				self?.willChangeValue(forKey: #keyPath(serverPort))
				self?.didChangeValue(forKey: #keyPath(serverPort))
			}
		}
	}

	private func stopObservingObjectValue() {
		serverPortObservation?.invalidate()
		serverPortObservation = nil
	}
}
