// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** Everything the window edits that Save writes: the configuration and the
 fields it is edited through as text. Secrets are tracked by whether they were
 typed into, because their stored values are read after the window opens. */
struct ServerPropertiesEditState: Equatable {
	let config: ServerConfig
	let serverAddress: String
	let serverPort: String
	let proxyAddress: String
	let proxyPort: String
	let proxyUsername: String
	let alternateNicknames: String
	let connectCommands: String
}

extension ServerPropertiesModel {
	/// The edits as they stand.
	var editState: ServerPropertiesEditState {
		ServerPropertiesEditState(
			config: config,
			serverAddress: serverAddress,
			serverPort: serverPort,
			proxyAddress: proxyAddress,
			proxyPort: proxyPort,
			proxyUsername: proxyUsername,
			alternateNicknames: alternateNicknames,
			connectCommands: connectCommands
		)
	}

	/** Whether there is anything Save would write that is not saved yet.

	 A new connection counts as soon as it has moved past the network list,
	 because nothing of it exists until it is saved. */
	var hasUnsavedChanges: Bool {
		if isNewServer {
			return templatePicker == nil
		}
		return editedSecretFields.isEmpty == false || savedEditState != editState
	}

	/** Records `saved` as what the window now edits from.

	 The fields keep what was typed, because that is what was saved; the
	 secrets typed into are no longer edits, so a second Save leaves them
	 alone. */
	func markSaved(_ saved: ServerConfig) {
		config = saved
		editedSecretFields = []
		savedEditState = editState
	}
}
