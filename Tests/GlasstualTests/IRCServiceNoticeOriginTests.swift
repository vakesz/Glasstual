@testable import Glasstual
import Testing

/// Replying to a `NickServ` notice sends the account password, so the notice
/// has to look like it came from network services first.
@Suite("Service notice origin")
@MainActor
struct IRCServiceNoticeOriginTests {
	private func isFromServices(
		senderIsServer: Bool = false,
		senderAddress: String? = nil,
		serverAddress: String? = "irc.example.net"
	) -> Bool {
		IRCServiceNoticePolicy.noticeIsFromServices(
			senderIsServer: senderIsServer,
			senderAddress: senderAddress,
			serverAddress: serverAddress
		)
	}

	@Test("A notice from the server itself is accepted")
	func serverNoticeIsAccepted() {
		#expect(isFromServices(senderIsServer: true))
	}

	@Test(
		"A services host is accepted",
		arguments: ["services.", "services.example.net", "SERVICES.EXAMPLE.NET", "nick.services.example.net"]
	)
	func servicesHostIsAccepted(host: String) {
		#expect(isFromServices(senderAddress: host))
	}

	@Test("A host under the network's own domain is accepted")
	func networkDomainIsAccepted() {
		#expect(isFromServices(senderAddress: "example.net", serverAddress: "irc.example.net"))
		#expect(isFromServices(senderAddress: "irc.example.net", serverAddress: "irc.example.net"))
	}

	@Test("An ordinary user holding the nickname is refused")
	func ordinaryUserIsRefused() {
		#expect(isFromServices(senderAddress: "cable-1-2-3-4.isp.example.com") == false)
	}

	@Test("A host that merely ends in the network's domain-like suffix is refused")
	func lookalikeHostIsRefused() {
		#expect(isFromServices(senderAddress: "evil-example.net", serverAddress: "irc.example.net") == false)
		#expect(isFromServices(senderAddress: "notservices.example.org", serverAddress: "irc.example.net") == false)
	}

	@Test("A sender with no host at all is refused")
	func missingHostIsRefused() {
		#expect(isFromServices(senderAddress: nil) == false)
		#expect(isFromServices(senderAddress: "") == false)
	}

	@Test("An unknown server address does not widen the check")
	func unknownServerAddressIsRefused() {
		#expect(isFromServices(senderAddress: "example.net", serverAddress: nil) == false)
	}
}
