// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CoreServices
import Foundation
import os

/** The quarantine mark a file received over DCC carries.

 A sandboxed process does not get `com.apple.quarantine` on files it creates
 unless its Info.plist opts in with `LSFileQuarantineEnabled`, and this app does
 not opt in for every file it writes. The bytes of a DCC transfer come from a
 stranger, so Gatekeeper and Launch Services must be told where they came from:
 each completed download is marked here, one file at a time. */
enum DCCQuarantine {
	/// What the mark records about the download.
	struct Origin: Equatable {
		let peerNickname: String
		let hostAddress: String
	}

	/** The `quarantineProperties` for a download from `origin`.

	 The agent is always the app. The origin URL is an `irc://` URL naming the
	 peer's address when it can be written as one, and is left out otherwise;
	 the peer's nickname is chosen by the sender and is never trusted as part of
	 a URL. */
	static func properties(for origin: Origin) -> [String: Any] {
		var properties: [String: Any] = [
			kLSQuarantineAgentNameKey as String: "Glasstual",
			kLSQuarantineTypeKey as String: kLSQuarantineTypeOtherDownload as String,
		]

		if let url = originURL(for: origin.hostAddress) {
			properties[kLSQuarantineOriginURLKey as String] = url
		}

		return properties
	}

	static func originURL(for hostAddress: String) -> URL? {
		let host = hostAddress.trimmingCharacters(in: .whitespacesAndNewlines)
		guard host.isEmpty == false, host.allSatisfy({ $0.isHexDigit || $0 == "." || $0 == ":" }) else {
			return nil
		}

		return URL(string: host.contains(":") ? "irc://[\(host)]/" : "irc://\(host)/")
	}

	/// Marks the file at `url`. A file that cannot be marked is logged and left
	/// as it is: the transfer already succeeded and is not undone for it.
	@discardableResult
	static func apply(to url: URL, origin: Origin) -> Bool {
		var values = URLResourceValues()
		values.quarantineProperties = properties(for: origin)
		var target = url

		do {
			try target.setResourceValues(values)
			return true
		} catch {
			let reason = error.localizedDescription
			fileTransferLogger.error("Could not quarantine a received file: \(reason, privacy: .public)")
			return false
		}
	}
}
