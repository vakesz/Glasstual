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
import Security
import SecurityInterface

extension ServerPropertiesSheet {
	@IBAction func preferredCipherSuitesChanged(_: Any?) {
		viewListOfPreferredCipherSuitesButton.isEnabled = preferredCipherSuitesButton
			.selectedTag() != Int(CipherSuiteCollection.none.rawValue)
	}

	@IBAction private func preferredCipherSuitesViewList(_: Any?) {
		let collection = CipherSuiteCollection(rawValue: UInt(preferredCipherSuitesButton.selectedTag())) ?? .default
		let descriptions = SecureTransportSupport
			.descriptions(forCipherListCollection: collection, withProtocol: true)
		TDCAlert.alertSheet(
			with: sheet,
			body: ServerPropertiesStrings.CipherSuites.description(descriptions.joined(separator: "\n")),
			title: ServerPropertiesStrings.CipherSuites.title(
				collectionName: preferredCipherSuitesButton.titleOfSelectedItem ?? ""
			),
			defaultButton: PromptStrings.Action.confirmation,
			alternateButton: nil,
			otherButton: nil
		)
	}

	@IBAction func proxyTypeChanged(_: Any?) {
		let proxyType = ServerPropertiesSheet.proxyType(forTag: proxyTypeButton.selectedTag())
		let isAutomatic = proxyType == .automatic
		let isTor = proxyType == .tor
		let socks = proxyType == .socks5
		let http = proxyType == .HTTP
		let enabled = socks || http
		contentViewProxyServerInputView.isHidden = !enabled
		contentViewProxyServerTorBrowserView.isHidden = !isTor
		contentViewProxyServerSystemSocksView.isHidden = !isAutomatic
		proxyAddressTextField.isEnabled = enabled
		proxyPortTextField.isEnabled = enabled
		proxyUsernameTextField.isEnabled = socks
		proxyPasswordTextField.isEnabled = socks
		proxyAddressTextField.performValidation()
		proxyPortTextField.performValidation()
	}

	@IBAction private func openProxySettingsInSystemPreferences(_: Any?) {
		PreferencesController.openProxySettingsInSystemPreferences()
	}

	private func copyCertificateCommand(from field: NSTextField) {
		NSPasteboard.general.textualStringContent = "/msg NickServ cert add \(field.stringValue)"
	}

	@IBAction private func onClientCertificateFingerprintSHA512CopyRequested(_: Any?) {
		copyCertificateCommand(from: clientCertificateSHA512FingerprintField)
	}

	@IBAction private func onClientCertificateFingerprintSHA2CopyRequested(_: Any?) {
		copyCertificateCommand(from: clientCertificateSHA2FingerprintField)
	}

	@IBAction private func onClientCertificateFingerprintSHA1CopyRequested(_: Any?) {
		copyCertificateCommand(from: clientCertificateSHA1FingerprintField)
	}

	private struct CertificateDetails {
		let commonName: String
		let sha512: String
		let sha256: String
		let sha1: String
	}

	private func clientCertificateDetails() -> CertificateDetails? {
		guard let persistentReference = config.identityClientSideCertificate else { return nil }
		let query: [CFString: Any] = [
			kSecClass: kSecClassCertificate,
			kSecValuePersistentRef: persistentReference,
			kSecReturnRef: true,
		]
		var result: CFTypeRef?
		guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
		      let result,
		      CFGetTypeID(result) == SecCertificateGetTypeID()
		else { return nil }
		let certificate = unsafeDowncast(result, to: SecCertificate.self)

		var commonNameReference: CFString?
		guard SecCertificateCopyCommonName(certificate, &commonNameReference) == errSecSuccess,
		      let commonName = commonNameReference as String?
		else { return nil }

		let data = SecCertificateCopyData(certificate) as Data
		return CertificateDetails(
			commonName: commonName,
			sha512: (data as NSData).textualSha512,
			sha256: (data as NSData).textualSha256,
			sha1: (data as NSData).textualSha1
		)
	}

	private func saveClientCertificate(identity: SecIdentity) {
		var certificate: SecCertificate?
		guard SecIdentityCopyCertificate(identity, &certificate) == errSecSuccess, let certificate else { return }
		let query: [CFString: Any] = [
			kSecClass: kSecClassCertificate,
			kSecValueRef: certificate,
			kSecReturnPersistentRef: true,
		]
		var result: CFTypeRef?
		guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
		      let persistentReference = result as? Data
		else { return }
		config.identityClientSideCertificate = persistentReference
		if prefersSecuredConnectionCheck.state == .off {
			prefersSecuredConnectionCheck.state = .on
			useSSLCheckChanged(nil)
		}
	}

	func updateClientCertificatePage() {
		let details = clientCertificateDetails()
		let emptyValue = ServerPropertiesStrings.Certificate.noneSelected
		clientCertificateCommonNameField.stringValue = details?.commonName ?? emptyValue
		clientCertificateSHA512FingerprintField.stringValue = details?.sha512.uppercased() ?? emptyValue
		clientCertificateSHA2FingerprintField.stringValue = details?.sha256.uppercased() ?? emptyValue
		clientCertificateSHA1FingerprintField.stringValue = details?.sha1.uppercased() ?? emptyValue
		let hasCertificate = details != nil
		clientCertificateResetCertificateButton.isEnabled = hasCertificate
		clientCertificateSHA512FingerprintCopyButton.isEnabled = hasCertificate
		clientCertificateSHA2FingerprintCopyButton.isEnabled = hasCertificate
		clientCertificateSHA1FingerprintCopyButton.isEnabled = hasCertificate
	}

	@IBAction private func onClientCertificateResetRequested(_: Any?) {
		config.identityClientSideCertificate = nil
		updateClientCertificatePage()
	}

	@IBAction private func onClientCertificateChangeRequested(_: Any?) {
		let query: [CFString: Any] = [
			kSecClass: kSecClassIdentity,
			kSecMatchLimit: kSecMatchLimitAll,
			kSecReturnRef: true,
		]
		var result: CFTypeRef?
		let status = SecItemCopyMatching(query as CFDictionary, &result)
		guard status == errSecSuccess, let identities = result as? [SecIdentity], !identities.isEmpty else {
			_ = TDCAlert.alert(
				withMessage: ServerPropertiesStrings.Certificate.noneAvailableExplanation,
				title: ServerPropertiesStrings.Certificate.noneAvailableTitle,
				defaultButton: PromptStrings.Action.confirmation,
				alternateButton: nil
			)
			return
		}

		guard let panel = SFChooseIdentityPanel.shared() else { return }
		clientCertificateSelectCertificatePanel = panel
		panel.setInformativeText(ServerPropertiesStrings.Certificate.chooseExplanation)
		panel.setAlternateButtonTitle(PromptStrings.Action.cancel)
		panel.beginSheet(
			for: sheet,
			modalDelegate: self,
			didEnd: #selector(chooseIdentityPanelDidEnd(_:returnCode:contextInfo:)),
			contextInfo: nil,
			identities: identities,
			message: ServerPropertiesStrings.Certificate.chooseTitle
		)
	}

	@objc private func chooseIdentityPanelDidEnd(
		_ panel: SFChooseIdentityPanel,
		returnCode: Int,
		contextInfo _: UnsafeMutableRawPointer?
	) {
		if returnCode == NSApplication.ModalResponse.OK.rawValue,
		   let identity = panel.identity()?.takeUnretainedValue()
		{
			saveClientCertificate(identity: identity)
			updateClientCertificatePage()
		}
		clientCertificateSelectCertificatePanel = nil
	}
}
