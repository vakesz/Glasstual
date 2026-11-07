// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import SwiftUI

/// What the editor holds while a network is being added or changed.
struct BouncerNetworkDraft: Identifiable {
	let id = UUID()
	/// The network being changed, or `nil` for a new one.
	let original: BouncerNetwork?
	var name = ""
	var host = ""
	var port = "6697"
	var usesTLS = true
	var nickname = ""
	var username = ""
	var realName = ""
	var password = ""

	init(editing network: BouncerNetwork? = nil) {
		original = network
		guard let network else { return }
		name = network.name ?? ""
		host = network.host ?? ""
		port = network.port.map(String.init) ?? port
		usesTLS = network.usesTLS ?? true
		nickname = network.nickname ?? ""
		username = network.username ?? ""
		realName = network.realName ?? ""
	}

	private var parsedPort: UInt16? {
		UInt16(port).flatMap { $0 > 0 ? $0 : nil }
	}

	var isValid: Bool {
		host.trimmingCharacters(in: .whitespaces).isEmpty == false && parsedPort != nil
			&& host.contains(where: \.isWhitespace) == false
	}

	/// What to send: everything for a new network, and for a change only what
	/// the person altered, so the rest stays as the bouncer has it.
	var edit: BouncerNetworkEdit {
		var edit = BouncerNetworkEdit()
		func changed(_ value: String, _ original: String?) -> String? {
			value == (original ?? "") && self.original != nil ? nil : value
		}
		edit.name = changed(name, original?.name)
		edit.host = changed(host, original?.host)
		if original == nil || parsedPort != original?.port {
			edit.port = parsedPort
		}
		if original == nil || usesTLS != original?.usesTLS {
			edit.usesTLS = usesTLS
		}
		edit.nickname = changed(nickname, original?.nickname)
		edit.username = changed(username, original?.username)
		edit.realName = changed(realName, original?.realName)
		edit.password = password.isEmpty ? nil : password
		return edit
	}
}

struct BouncerNetworkEditorView: View {
	@State var draft: BouncerNetworkDraft
	let confirm: (BouncerNetworkDraft) -> Void
	let cancel: () -> Void

	var body: some View {
		VStack(spacing: 0) {
			Form {
				Section {
					TextField(.ServerProperties.bouncerNetworkName, text: $draft.name)
					TextField(.ServerProperties.bouncerNetworkHost, text: $draft.host)
					TextField(.ServerProperties.bouncerNetworkPort, text: $draft.port)
					Toggle(.ServerProperties.bouncerNetworkSecure, isOn: $draft.usesTLS)
				}
				Section {
					TextField(.ServerProperties.bouncerNetworkNickname, text: $draft.nickname)
					TextField(.ServerProperties.bouncerNetworkUsername, text: $draft.username)
					TextField(.ServerProperties.bouncerNetworkRealName, text: $draft.realName)
					SecureField(.ServerProperties.bouncerNetworkPassword, text: $draft.password)
				} footer: {
					if draft.original != nil {
						Text(.ServerProperties.bouncerNetworkPasswordKept)
					}
				}
			}
			.formStyle(.grouped)

			SheetActions(
				confirmTitle: Text(PromptStrings.Action.save),
				confirmIsDisabled: draft.isValid == false,
				confirm: { confirm(draft) },
				cancel: cancel
			)
		}
		.frame(minWidth: 460, minHeight: 440)
	}
}
