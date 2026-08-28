@testable import Glasstual
import Testing

/// `ModeInfo` used to be an immutable class with a mutable subclass. It is now a
/// value, so copies are independent and equality is structural.
@MainActor
struct IRCModeInfoValueTests {
	@Test("A copy can be changed without changing the original")
	func copiesAreIndependent() {
		let original = ModeInfo(modeSymbol: "k", modeIsSet: true, modeParameter: "secret")

		var changed = original
		changed.modeIsSet = false
		changed.modeParameter = nil

		#expect(original.modeIsSet)
		#expect(original.modeParameter == "secret")
		#expect(changed.modeIsSet == false)
		#expect(changed.modeParameter == nil)
	}

	@Test("Equality and hashing use every field")
	func equalityUsesEveryField() {
		let first = ModeInfo(modeSymbol: "k", modeIsSet: true, modeParameter: "secret")
		var second = first

		#expect(first == second)
		#expect(first.hashValue == second.hashValue)

		second.modeParameter = "other"

		#expect(first != second)
	}

	@Test("The parameter defaults are the ones the old convenience initialisers gave")
	func defaultsMatchTheRetiredConvenienceInitialisers() {
		let bare = ModeInfo(modeSymbol: "n")
		let set = ModeInfo(modeSymbol: "t", modeIsSet: true)

		#expect(bare.modeSymbol == "n")
		#expect(bare.modeIsSet == false)
		#expect(bare.modeParameter == nil)
		#expect(set.modeIsSet)
		#expect(set.modeParameter == nil)
	}

	@Test("Modes parsed off a MODE line survive being stored and read back")
	func parsedModesRoundTripThroughTheContainer() {
		let client = GLTTestClient()
		client.supportInfo.processConfigurationData("PREFIX=(ov)@+")

		let parsed = client.supportInfo.parseModes("+nt-k+l secret 10")
		let container = ChannelModeContainer(client: client)
		container.apply(parsed)

		#expect(parsed.isEmpty == false)

		for mode in parsed {
			#expect(container.modeInfo(for: mode.modeSymbol) == mode)
		}
	}
}
