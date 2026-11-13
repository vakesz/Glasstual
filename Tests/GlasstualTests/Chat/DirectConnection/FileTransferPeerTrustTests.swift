// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

@testable import Glasstual
import Testing

/** A tracked nickname is not an identity. An entry counts as pinning the sender
 only when its host is written out; a wildcard in the host is open to anyone
 the pattern reaches, and the sender chooses nothing about a literal one. */
@Suite("File transfer peer trust")
struct FileTransferPeerTrustTests {
	private func trusted(entry: String, sender: String? = "mara!m@home.example.org", account: String? = nil) -> Bool {
		FileTransferPeerTrust.isTrusted(
			senderHostmask: sender,
			senderAccount: account,
			trackedNickname: "mara",
			entryHostmask: entry,
			caseMapping: .rfc1459
		)
	}

	@Test("A literal host pins the sender, whatever the user part is", arguments: [
		"mara!m@home.example.org", "mara!*@home.example.org", "mara!?@home.example.org",
	])
	func literalHostPins(entry: String) {
		#expect(trusted(entry: entry))
		#expect(trusted(entry: entry, sender: "mara!m@evil.example.net") == false)
	}

	@Test("A wildcard in the host pins nobody", arguments: [
		"mara!m@*", "mara!*@*.example.org", "mara!m@home.example.*", "mara!m@home.exampl?.org", "mara!m@",
		"mara!*@*", "mara", "mara!m",
	])
	func wildcardHostDoesNotPin(entry: String) {
		#expect(trusted(entry: entry) == false)
	}

	@Test("An escaped wildcard in the host is an ordinary character")
	func escapedWildcardIsLiteral() {
		#expect(trusted(entry: #"mara!m@host\*.example.org"#, sender: "mara!m@host*.example.org"))
		#expect(trusted(entry: #"mara!m@host\*.example.org"#, sender: "mara!m@hostile.example.org") == false)
	}

	@Test("A services account still vouches for an entry that pins no host")
	func accountStillVouches() {
		#expect(trusted(entry: "mara!*@*", account: "Mara"))
		#expect(trusted(entry: "mara!m@*.example.org", account: "mara"))
		#expect(trusted(entry: "mara!*@*", account: "*") == false)
	}
}
