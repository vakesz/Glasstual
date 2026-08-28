/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2019 Codeux Software, LLC & respective contributors.
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

import AppKit
import CocoaExtensions

extension ServerPropertiesSheet: ServerEndpointListSheetDelegate, ValidatedControlChangeObserver {
	func loadPrimaryServerEndpoint() {
		guard let server = serverList.first else {
			serverAddressComboBox.stringValue = ""
			serverPortTextField.integerValue = Int(IRCConnectionDefaults.serverPort)
			prefersSecuredConnectionCheck.state = .off
			serverPasswordTextField.stringValue = ""
			return
		}

		populatingPrimaryServer = true
		if let network = networkList.network(withServerAddress: server.serverAddress) {
			serverAddressComboBox.stringValue = network.networkName
		} else {
			serverAddressComboBox.stringValue = server.serverAddress
		}
		serverPortTextField.integerValue = Int(server.serverPort)
		prefersSecuredConnectionCheck.state = server.prefersSecuredConnection ? .on : .off
		serverPasswordTextField.stringValue = server.serverPassword ?? ""
		populatingPrimaryServer = false
	}

	private func restorePreviousValuesForPrimaryServer() {
		guard let previousPrimaryServer else { return }
		populatingPrimaryServer = true
		serverPortTextField.integerValue = Int(previousPrimaryServer.serverPort)
		prefersSecuredConnectionCheck.state = previousPrimaryServer.prefersSecuredConnection ? .on : .off
		self.previousPrimaryServer = nil
		populatingPrimaryServer = false
	}

	private func saveCurrentValuesForPrimaryServer() {
		guard previousPrimaryServer == nil else { return }
		if let server = serverList.first {
			previousPrimaryServer = server
			return
		}
		previousPrimaryServer = Server(
			serverPort: UInt16(clamping: serverPortTextField.integerValue),
			prefersSecuredConnection: prefersSecuredConnectionCheck.state == .on
		)
	}

	private func populateDefaultsForPreconfiguredNetwork() {
		guard !populatingPrimaryServer else { return }
		let address = serverAddressComboBox.value
		guard address != lastServerAddressValue else { return }
		lastServerAddressValue = address
		guard let network = networkList.network(named: address) ?? networkList.network(withServerAddress: address)
		else {
			restorePreviousValuesForPrimaryServer()
			return
		}

		populatingPrimaryServer = true
		if !serverAddressComboBox.valueIsPredefined {
			serverAddressComboBox.stringValue = network.networkName
			lastServerAddressValue = network.networkName
		}
		saveCurrentValuesForPrimaryServer()
		serverPortTextField.integerValue = Int(network.serverPort)
		prefersSecuredConnectionCheck.state = network.prefersSecuredConnection ? .on : .off
		populatingPrimaryServer = false
	}

	@IBAction func useSSLCheckChanged(_: Any?) {
		let secured = prefersSecuredConnectionCheck.state == .on
		if secured, serverPortTextField.integerValue == 6667 {
			serverPortTextField.stringValue = "6697"
		} else if !secured, serverPortTextField.integerValue == 6697 {
			serverPortTextField.stringValue = "6667"
		}
		rebuildMutableServerEndpointListIfNeeded()
	}

	public func controlTextDidChange(_ notification: Notification) {
		if notification.object as AnyObject? === serverPasswordTextField {
			rebuildMutableServerEndpointListIfNeeded()
		}
	}

	public func validatedTextFieldTextDidChange(_ sender: NSControl) {
		if sender === serverAddressComboBox {
			populateDefaultsForPreconfiguredNetwork()
			rebuildMutableServerEndpointListIfNeeded()
		} else if sender === serverPortTextField {
			rebuildMutableServerEndpointListIfNeeded()
		}
	}

	@IBAction private func preferredInternetProtocolChanged(_ sender: Any?) {
		config.connectionPrefersIPv4 = false
		let tag = (sender as? NSControl)?.tag ?? 0
		config.addressType = IRCConnectionAddressType(rawValue: UInt(tag)) ?? .default
	}

	@IBAction private func editSeverEndpoints(_: Any?) {
		let controller = ServerEndpointListSheet(window: sheet)
		controller.delegate = self
		controller.start(with: serverList)
		serverEndpointSheet = controller
	}

	public func serverEndpointListSheet(_: ServerEndpointListSheet, onOk serverList: [Server]) {
		serverListArrayController.textual_removeAllArrangedObjects()
		serverListArrayController.add(contentsOf: serverList)
		loadPrimaryServerEndpoint()
	}

	public func serverEndpointListSheetWillClose(_: ServerEndpointListSheet) {
		serverEndpointSheet = nil
	}

	private func rebuildMutableServerEndpointList() {
		guard !populatingPrimaryServer else { return }
		var server = serverList.first ?? Server()
		let address = serverAddressComboBox.value
		server.serverAddress = networkList.network(named: address)?.serverAddress ?? address.lowercased()
		server.serverPort = UInt16(clamping: serverPortTextField.integerValue)
		server.prefersSecuredConnection = prefersSecuredConnectionCheck.state == .on
		server.serverPassword = serverPasswordTextField.stringValue
			.trimmingCharacters(in: .whitespacesAndNewlines)
		if serverList.isEmpty {
			serverListArrayController.addObject(server)
		} else {
			serverListArrayController.textual_replaceObject(atArrangedObjectIndex: 0, with: server)
		}
	}

	private func rebuildMutableServerEndpointListIfNeeded() {
		guard serverEndpointSheet == nil else { return }
		rebuildMutableServerEndpointList()
	}
}
