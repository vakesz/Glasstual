/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import CocoaExtensions
import Foundation
@testable import Glasstual
import Testing

/** The network list a new connection sheet opens on.

 Add Server used to open a blank form, and the only trace of the bundled
 catalog was the address field's completion. The sheet now leads with the
 list, and Continue fills the form in from the chosen network. */
@MainActor
@Suite("Server properties templates")
struct ServerPropertiesTemplateTests {
	private static func catalog() throws -> NetworkList {
		try NetworkList(networks: [
			#require(Network(dictionary: [
				"name": .string("Libera.Chat"),
				"serverAddress": .string("irc.libera.chat"),
				"serverPort": .integer(6697),
				"prefersSecuredConnection": .boolean(true),
				"saslSupported": .boolean(true),
				"suggestedChannels": .array([.string("#libera"), .string("#swift")]),
			])),
			#require(Network(dictionary: [
				"name": .string("Rizon"),
				"serverAddress": .string("irc.rizon.net"),
				"serverPort": .integer(6667),
				"prefersSecuredConnection": .boolean(false),
				"saslSupported": .boolean(false),
			])),
		])
	}

	private static func newConnectionModel() throws -> ServerPropertiesModel {
		try ServerPropertiesModel(config: ClientConfig(), networkList: catalog(), offersTemplates: true)
	}

	@Test("A new connection opens on the network list; an existing one opens on the form")
	func onlyANewConnectionOffersTemplates() throws {
		let new = try Self.newConnectionModel()
		#expect(new.isChoosingTemplate)
		#expect(new.canApplyTemplate == false)

		let existing = try ServerPropertiesModel(config: ClientConfig(), networkList: Self.catalog())
		#expect(existing.isChoosingTemplate == false)
		#expect(existing.templatePicker == nil)
	}

	@Test("Choosing a network fills the form in and moves on to it")
	func networkFillsTheFormIn() throws {
		let model = try Self.newConnectionModel()
		let picker = try #require(model.templatePicker)
		picker.selection = .network("libera.chat")
		#expect(model.canApplyTemplate)

		model.applySelectedTemplate()

		#expect(model.isChoosingTemplate == false)
		#expect(model.selection == .general)
		#expect(model.config.connectionName == "Libera.Chat")
		#expect(model.serverAddress == "Libera.Chat")
		#expect(model.resolvedPrimaryServerAddress == "irc.libera.chat")
		#expect(model.serverPort == "6697")
		#expect(model.primaryServerIsSecured)
		#expect(model.config.usesSASL)
		#expect(model.config.channelList.map(\.channelName) == ["#libera", "#swift"])
		#expect(model.config.channelList.map(\.autoJoin) == [true, true])
	}

	@Test("A network without SASL or suggested channels leaves both off")
	func plainNetworkLeavesSASLAndChannelsOff() throws {
		let model = try Self.newConnectionModel()
		try #require(model.templatePicker).selection = .network("rizon")

		model.applySelectedTemplate()

		#expect(model.config.connectionName == "Rizon")
		#expect(model.serverPort == "6667")
		#expect(model.primaryServerIsSecured == false)
		#expect(model.config.usesSASL == false)
		#expect(model.config.channelList.isEmpty)
	}

	/// The row for a host the catalog does not list is a way past the list,
	/// not a template: the form opens exactly as it did before there was one.
	@Test("The custom server row moves on to an untouched form")
	func customServerLeavesTheFormUntouched() throws {
		let model = try Self.newConnectionModel()
		let before = model.config
		try #require(model.templatePicker).selection = .customServer
		#expect(model.canApplyTemplate)

		model.applySelectedTemplate()

		#expect(model.isChoosingTemplate == false)
		#expect(model.config == before)
	}

	@Test("Continue does nothing until a row is chosen")
	func continueNeedsASelection() throws {
		let model = try Self.newConnectionModel()

		model.applySelectedTemplate()

		#expect(model.isChoosingTemplate)
	}

	/// The template's endpoint goes through the same address display rule the
	/// form uses, so what the person sees after Continue is what typing the
	/// network's name would have shown.
	@Test("The applied endpoint is what the form would store for a typed network name")
	func appliedTemplateMatchesTypedNetwork() throws {
		let typed = try ServerPropertiesModel(config: ClientConfig(), networkList: Self.catalog())
		typed.serverAddress = "Libera.Chat"
		typed.serverAddressTextDidChange()

		let chosen = try Self.newConnectionModel()
		try #require(chosen.templatePicker).selection = .network("libera.chat")
		chosen.applySelectedTemplate()

		#expect(chosen.config.serverList.first?.serverAddress == typed.resolvedPrimaryServerAddress)
		#expect(chosen.config.serverList.first?.serverPort == UInt16(typed.serverPort))
		#expect(chosen.config.serverList.first?.prefersSecuredConnection == typed.primaryServerIsSecured)
	}
}
