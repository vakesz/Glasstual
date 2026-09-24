import Foundation
@testable import Glasstual
import Testing

/// Replying to a `NickServ` notice sends the account password, so the notice
/// has to look like it came from network services first.
@Suite("Service notice origin")
@MainActor
struct ServiceNoticeOriginTests {
	private func isFromServices(
		senderIsServer: Bool = false,
		senderAddress: String? = nil,
		serverAddress: String? = "irc.example.net"
	) -> Bool {
		ServiceNoticePolicy.noticeIsFromServices(
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
		"A services host on the network's domain is accepted",
		arguments: ["services.", "services.example.net", "SERVICES.EXAMPLE.NET", "nick.services.example.net"]
	)
	func servicesHostIsAccepted(host: String) {
		#expect(isFromServices(senderAddress: host))
	}

	/// A reverse DNS name is whatever the owner of the address publishes, so a
	/// `services` label is only evidence on the network's own domain.
	@Test(
		"A services host outside the network's domain is refused",
		arguments: ["services.attacker.example", "services.example.net.attacker.example", "nick.services.net", "services.net"]
	)
	func servicesHostElsewhereIsRefused(host: String) {
		#expect(isFromServices(senderAddress: host) == false)
	}

	@Test("A services host is judged against the server the session is on")
	func servicesHostFollowsTheServerName() {
		#expect(isFromServices(senderAddress: "services.libera.chat", serverAddress: "tantalum.libera.chat"))
		#expect(isFromServices(senderAddress: "services.libera.chat", serverAddress: "irc.example.net") == false)
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

	private func nickServContext(
		identifiedWithSASL: Bool = false,
		permitsCredentialsInClear: Bool = true
	) -> ServiceNoticePolicy.NickServContext {
		.init(
			isWaiting: false,
			isIdentifiedWithSASL: identifiedWithSASL,
			permitsCredentialsInClear: permitsCredentialsInClear,
			password: "secret",
			nickname: "alice",
			serverAddress: "irc.example.net",
			sendsAuthenticationToUserServ: false,
			needsIdentificationTokens: ["nickname is registered"],
			successfulIdentificationTokens: ["now identified"]
		)
	}

	@Test("An account SASL already authenticated is not identified again")
	func saslIdentifiedAccountSendsNoPassword() {
		let action = ServiceNoticePolicy.nickServAction(
			for: "This nickname is registered",
			context: nickServContext(identifiedWithSASL: true)
		)

		#expect(action == nil)
	}

	@Test("A password is withheld from a connection that lost the encryption it asked for")
	func passwordIsWithheldWithoutEncryption() {
		let action = ServiceNoticePolicy.nickServAction(
			for: "This nickname is registered",
			context: nickServContext(permitsCredentialsInClear: false)
		)

		#expect(action == .identificationWithheld)
	}

	/// Filing a `[#channel]` notice into that channel is a claim only services
	/// may make, so an impostor's notice stays where it arrived.
	@Test("A ChanServ notice from an ordinary user is not filed into the channel it names", arguments: [true, false])
	func chanServNoticeRoutingNeedsServices(_ fromServices: Bool) throws {
		var settings = ChatSettings()
		settings.locationToSendNotices = .serverConsole
		let session = TestServerSession(
			configDictionary: ["nickname": "alice"],
			nicknamePassword: nil,
			fixture: ChatEnvironmentFixture(settings: settings)
		)
		session.setConnectionTransportForTesting(.connected)
		session.supportInfo.serverAddress = "irc.example.net"
		let channel = try #require(session.findConversationOrCreate("#swift", as: .channel))
		let host = fromServices ? "services.example.net" : "cable.isp.example.com"
		let message = try #require(Message(
			line: ":ChanServ!ChanServ@\(host) NOTICE alice :[#swift] Welcome",
			on: session
		))

		session.receivePrivmsgAndNotice(message)

		let printed = try #require(session.printedLines.lastObject as? [String: Any])
		#expect((printed["channel"] as? Conversation === channel) == fromServices)
		#expect((printed["messageBody"] as? String == "Welcome") == fromServices)
	}
}
