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

enum ServerPropertiesValidation {
	static func isNickname(_ value: String) -> Bool {
		(value as NSString).isHostmaskNickname
	}

	static func isUsername(_ value: String) -> Bool {
		(value as NSString).isHostmaskUsername
	}

	static func isInternetAddress(_ value: String) -> Bool {
		(value as NSString).isValidInternetAddress
	}

	static func isInternetPort(_ value: String) -> Bool {
		(value as NSString).isValidInternetPort
	}

	static func isSingleLine(_ value: String) -> Bool {
		value.rangeOfCharacter(from: .newlines) == nil
	}

	/// The longest quit or away message a server will carry.
	static let maximumCommentLength = 390

	static func isLeavingComment(_ value: String) -> Bool {
		isSingleLine(value) && value.count <= maximumCommentLength
	}

	static func areAlternateNicknamesValid(_ value: String) -> Bool {
		invalidAlternateNickname(in: value) == nil
	}

	/// The first nickname in a whitespace-separated list that is not valid, so
	/// the field can name it.
	static func invalidAlternateNickname(in value: String) -> String? {
		value.components(separatedBy: .whitespaces).first { isNickname($0) == false }
	}
}

extension ServerPropertiesSheet {
	func configureValidatedFields() {
		configure(alternateNicknamesTextField, invalidOnEmpty: false, firstTokenOnly: false) { value in
			ServerPropertiesValidation.invalidAlternateNickname(in: value)
				.map(ServerPropertiesStrings.Validation.invalidAlternateNickname)
		}

		configure(awayNicknameTextField, invalidOnEmpty: false, firstTokenOnly: true) { value in
			ServerPropertiesValidation.isNickname(value) ? nil : CommonValidationStrings.invalidNickname
		}
		configure(nicknameTextField, invalidOnEmpty: true, firstTokenOnly: true) { value in
			ServerPropertiesValidation.isNickname(value) ? nil : CommonValidationStrings.invalidNickname
		}
		configure(usernameTextField, invalidOnEmpty: true, firstTokenOnly: true) { value in
			ServerPropertiesValidation.isUsername(value)
				? nil
				: ServerPropertiesStrings.Validation.invalidUsername
		}
		configure(ctcpVersionReplyTextField, invalidOnEmpty: false, firstTokenOnly: false)
		configure(realNameTextField, invalidOnEmpty: true, firstTokenOnly: false) { value in
			ServerPropertiesValidation.isSingleLine(value)
				? nil
				: ServerPropertiesStrings.Validation.invalidRealName
		}

		let maximumLength = ServerPropertiesValidation.maximumCommentLength
		let leavingCommentValidation: (String) -> String? = { value in
			if !ServerPropertiesValidation.isSingleLine(value) {
				return CommonValidationStrings.singleLineRequired
			}
			return value.count > maximumLength ? CommonValidationStrings.maximumLength(maximumLength) : nil
		}
		configure(
			normalLeavingCommentTextField,
			invalidOnEmpty: false,
			firstTokenOnly: false,
			validation: leavingCommentValidation
		)
		configure(
			sleepModeQuitMessageTextField,
			invalidOnEmpty: false,
			firstTokenOnly: false,
			validation: leavingCommentValidation
		)
		configure(connectionNameTextField, invalidOnEmpty: true, firstTokenOnly: false) { value in
			ServerPropertiesValidation.isSingleLine(value) ? nil : CommonValidationStrings.singleLineRequired
		}
		configure(serverPortTextField, invalidOnEmpty: true, firstTokenOnly: false) { value in
			ServerPropertiesValidation.isInternetPort(value) ? nil : CommonValidationStrings.invalidInternetPort
		}

		serverAddressComboBox.textDidChangeCallback = self
		serverAddressComboBox.stringValueIsInvalidOnEmpty = true
		serverAddressComboBox.stringValueIsTrimmed = true
		serverAddressComboBox.stringValueUsesOnlyFirstToken = true
		serverAddressComboBox.validationBlock = { value in
			ServerPropertiesValidation.isInternetAddress(value) ? nil : CommonValidationStrings.invalidServerAddress
		}

		configure(proxyAddressTextField, invalidOnEmpty: false, firstTokenOnly: true) { [weak self] value in
			guard let self else { return nil }
			guard ServerPropertiesSheet.proxyTypeUsesAddress(proxyTypeButton.selectedTag())
			else { return nil }
			return ServerPropertiesValidation.isInternetAddress(value)
				? nil
				: ServerPropertiesStrings.Validation.invalidProxyAddress
		}
		proxyAddressTextField.performValidationWhenEmpty = true

		configure(proxyPortTextField, invalidOnEmpty: false, firstTokenOnly: false) { [weak self] value in
			guard let self else { return nil }
			guard ServerPropertiesSheet.proxyTypeUsesAddress(proxyTypeButton.selectedTag())
			else { return nil }
			return ServerPropertiesValidation.isInternetPort(value) ? nil : CommonValidationStrings.invalidInternetPort
		}
		proxyPortTextField.performValidationWhenEmpty = true
		proxyPortTextField.defaultValue = String(IRCConnectionDefaults.proxyPort)
	}

	private func configure(
		_ textField: ValidatedTextField,
		invalidOnEmpty: Bool,
		firstTokenOnly: Bool,
		validation: ((String) -> String?)? = nil
	) {
		textField.textDidChangeCallback = self
		textField.stringValueIsInvalidOnEmpty = invalidOnEmpty
		textField.stringValueIsTrimmed = true
		textField.stringValueUsesOnlyFirstToken = firstTokenOnly
		textField.validationBlock = validation
	}

	func okOrError() -> Bool {
		let current = ServerPropertiesSelection(rawValue: navigationOutlineView.selectedItem?.identifier ?? 0) ??
			.default
		guard okOrError(for: current) else { return false }
		for selection in [ServerPropertiesSelection.general, .identity, .disconnectMessages, .proxyServer]
			where selection != current
		{
			guard okOrError(for: selection) else { return false }
		}
		return true
	}

	private func okOrError(for selection: ServerPropertiesSelection) -> Bool {
		let fields: [AnyObject]
		switch selection {
		case .general: fields = [connectionNameTextField, serverAddressComboBox, serverPortTextField]
		case .identity: fields = [
				nicknameTextField,
				awayNicknameTextField,
				alternateNicknamesTextField,
				usernameTextField,
				realNameTextField,
			]
		case .disconnectMessages: fields = [normalLeavingCommentTextField, sleepModeQuitMessageTextField]
		case .proxyServer: fields = [proxyAddressTextField, proxyPortTextField]
		default: return true
		}
		for field in fields {
			let isValid = (field as? ValidatedTextField)?.valueIsValid ?? (field as? ValidatedComboBox)?
				.valueIsValid ?? true
			if !isValid {
				navigate(to: selection)
				DispatchQueue.main.async {
					(field as? ValidatedTextField)?.showValidationErrorPopover()
					(field as? ValidatedComboBox)?.showValidationErrorPopover()
				}
				return false
			}
		}
		return true
	}
}
