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
 *********************************************************************** */

import AppKit

/// The table's columns, named the way the nib identifies them. A cell view
/// learns which column it is drawing from its own identifier, which the nib
/// gives it.
nonisolated enum ServerEndpointColumn: String { // nonisolated: value
	case serverAddress
	case serverPort
	case prefersSecuredConnection
	case serverPassword
}

/** Everything the nib used to get from bindings.

 Each column was bound with `NSValidatesImmediately`, so an address or a port
 the person typed reached `NSObject.validateValue(_:forKey:)` on the cell view
 before it reached the model, and an editor that threw was rejected. There is
 no KVC hook left to hang that on, so the rules are stated here as pure
 functions over the value and called when editing ends. */
nonisolated enum ServerEndpointValidation { // nonisolated: value
	static let errorDomain = "GlasstualErrorDomain"
	static let invalidAddressCode = 71013
	static let invalidPortCode = 71014

	/// The ports a person did not choose: the defaults each transport implies.
	/// Ticking "connect securely" moves between them, and leaves any other port
	/// alone because that one was chosen deliberately.
	static let plainTextPort: UInt16 = 6667
	static let securedPort: UInt16 = 6697

	static func validatedAddress(_ address: String) throws -> String {
		guard (address as NSString).isValidInternetAddress else {
			throw NSError(
				domain: errorDomain,
				code: invalidAddressCode,
				userInfo: [
					NSLocalizedDescriptionKey: ServerEndpointStrings.invalidAddressDescription,
					NSLocalizedRecoverySuggestionErrorKey: ServerEndpointStrings.invalidAddressRecoverySuggestion,
				]
			)
		}

		return address
	}

	static func validatedPort(_ port: String) throws -> UInt16 {
		guard (port as NSString).isValidInternetPort, let value = UInt16(port) else {
			throw NSError(
				domain: errorDomain,
				code: invalidPortCode,
				userInfo: [
					NSLocalizedDescriptionKey: ServerEndpointStrings.invalidPortDescription,
					NSLocalizedRecoverySuggestionErrorKey: ServerEndpointStrings.invalidPortRecoverySuggestion,
				]
			)
		}

		return value
	}

	/// `server` with its transport switched, carrying the port with it.
	static func server(_ server: Server, preferringSecuredConnection prefers: Bool) -> Server {
		var updated = server
		updated.prefersSecuredConnection = prefers

		if prefers, server.serverPort == plainTextPort {
			updated.serverPort = securedPort
		} else if prefers == false, server.serverPort == securedPort {
			updated.serverPort = plainTextPort
		}

		return updated
	}
}

/// Where a cell view sends an edit. The sheet owns the endpoints; a cell only
/// draws one and reports what the person typed into it.
@MainActor
protocol ServerEndpointListCellDelegate: AnyObject {
	func endpointCell(_ cell: ServerEndpointListSheetTableCellView, didEdit server: Server)
	func endpointCell(
		_ cell: ServerEndpointListSheetTableCellView,
		didRejectEditWith error: any Error
	)
}

/** One cell of the server-endpoint table.

 Each of the four columns has its own prototype of this class; the column's
 identifier is what tells an instance which field of the endpoint it draws. The
 nib used to bind a control to a mirrored `dynamic` property here, which
 read and wrote the row through KVC — including a KVO republish so the port cell
 would redraw when the checkbox in the security cell moved the port. None of
 that survives: the cell is handed a value, and hands an edit back. */
@objc(TDCServerEndpointListSheetTableCellView)
public final class ServerEndpointListSheetTableCellView: NSTableCellView {
	/// The securely-connect column draws a checkbox rather than a text field,
	/// so it needs an outlet of its own.
	@IBOutlet var checkbox: NSButton?

	weak var editDelegate: (any ServerEndpointListCellDelegate)?

	private(set) var server: Server?

	private var column: ServerEndpointColumn? {
		identifier.flatMap { ServerEndpointColumn(rawValue: $0.rawValue) }
	}

	/// True while the person is typing in this cell. Redrawing then would take
	/// the half-typed text away from them.
	var isBeingEdited: Bool {
		textField?.currentEditor() != nil
	}

	func configure(with server: Server, delegate: any ServerEndpointListCellDelegate) {
		editDelegate = delegate

		refresh(with: server)
	}

	/// Re-draws the cell from `server` without disturbing an edit in progress.
	func refresh(with server: Server) {
		self.server = server

		guard isBeingEdited == false else {
			return
		}

		switch column {
		case .serverAddress:
			drawTextField(showing: server.serverAddress)
		case .serverPort:
			drawTextField(showing: String(server.serverPort))
		case .serverPassword:
			drawTextField(showing: server.serverPassword ?? "")
		case .prefersSecuredConnection:
			checkbox?.state = server.prefersSecuredConnection ? .on : .off
			checkbox?.target = self
			checkbox?.action = #selector(securedConnectionToggled(_:))
		case nil:
			break
		}
	}

	private func drawTextField(showing value: String) {
		guard let textField else {
			return
		}

		textField.stringValue = value
		textField.target = self
		textField.action = #selector(textFieldEdited(_:))
	}

	@objc private func textFieldEdited(_ sender: NSTextField) {
		guard let server, let column else {
			return
		}

		do {
			var edited = server

			switch column {
			case .serverAddress:
				edited.serverAddress = try ServerEndpointValidation.validatedAddress(sender.stringValue)
			case .serverPort:
				edited.serverPort = try ServerEndpointValidation.validatedPort(sender.stringValue)
			case .serverPassword:
				edited.serverPassword = sender.stringValue
			case .prefersSecuredConnection:
				return
			}

			self.server = edited
			editDelegate?.endpointCell(self, didEdit: edited)
		} catch {
			/* Put back what the endpoint still says, so the field never shows a
			 value the model rejected. Written straight to the control rather
			 than through `refresh`, because the field editor is still attached
			 while the end-of-editing action runs. */
			switch column {
			case .serverAddress:
				drawTextField(showing: server.serverAddress)
			case .serverPort:
				drawTextField(showing: String(server.serverPort))
			default:
				break
			}

			editDelegate?.endpointCell(self, didRejectEditWith: error)
		}
	}

	@objc private func securedConnectionToggled(_ sender: NSButton) {
		guard let server else {
			return
		}

		let edited = ServerEndpointValidation.server(
			server,
			preferringSecuredConnection: sender.state == .on
		)

		self.server = edited
		editDelegate?.endpointCell(self, didEdit: edited)
	}
}
