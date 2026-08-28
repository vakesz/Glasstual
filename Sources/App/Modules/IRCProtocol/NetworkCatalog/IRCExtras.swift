/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\\___/_/\\_\\__|\\__,_|\\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import AppKit
import CocoaExtensions
import os

public typealias IRCExtras = Extras

private let extrasLogger = Logger(
	subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
	category: "IRCExtras"
)

@objc(IRCExtras)
@MainActor
public final class Extras: NSObject {
	// MARK: - Glasstual URL Scheme

	private static func performSpecialActionForGlasstualScheme(_ action: String, source sourceLocation: String) {
		/*
		 Syntax: glasstual://<token>

		 Reserved tokens:

		 acknowledgements					— Open acknowledgements file
		 application-support-folder			— Open the Application Support folder
		 contributors						— Open contributors file
		 custom-scripts-folder				– Open the custom scripts storage location folder
		 custom-style-folder					— Open the custom style storage location folder
		 custom-styles-folder				— Open the custom style storage location folder
		 diagnostic-reports-folder			— System diagnostic reports folder
		 goto 								— Navigate to an item
		 support-channel						— Connect to the #glasstual channel
		 testing-channel						— Connect to the #glasstual-testing channel
		 unsupervised-script-folder			— Open the custom scripts storage location folder
		 unsupervised-scripts-folder			— Open the custom scripts storage location folder
		 */

		let menuController = NSObject.applicationController().menuController

		if action == "acknowledgements" {
			menuController?.openAcknowledgements(nil)
		} else if action == "application-support-folder" {
			if let url = PathInfo.groupContainerApplicationSupportURL {
				NSWorkspace.shared.open(url)
			}
		} else if action == "contributors" {
			menuController?.openAcknowledgements(nil)
		} else if action == "custom-scripts-folder"
			|| action == "unsupervised-script-folder"
			|| action == "unsupervised-scripts-folder"
		{
			if let url = PathInfo.customScriptsURL {
				NSWorkspace.shared.open(url)
			}
		} else if action == "custom-style-folder" || action == "custom-styles-folder" {
			if let url = PathInfo.customThemesURL {
				NSWorkspace.shared.open(url)
			}
		} else if action == "diagnostic-reports-folder" {
			NSWorkspace.shared.open(PathInfo.userDiagnosticReportsURL)
			NSWorkspace.shared.open(PathInfo.systemDiagnosticReportsURL)
		} else if action == "goto" {
			if let url = URL(string: sourceLocation) {
				menuController?.perform(NSSelectorFromString("navigateToTreeItemAtURL:"), with: url)
			}
		} else if action == "support-channel" {
			menuController?.connectToGlasstualHelpChannel(nil)
		} else if action == "testing-channel" {
			menuController?.connectToGlasstualTestingChannel(nil)
		}
	}

	// MARK: - IRC Protocol URI Parsing

	@objc(parseIRCProtocolURI:)
	public static func parseIRCProtocolURI(_ location: String) {
		parseIRCProtocolURI(location, withDescriptor: nil)
	}

	/// Parses an `irc:`/`ircs:` URI into the server-info string and channel list
	/// that `createConnectionToServer` understands. Pure; no side effects.
	nonisolated static func intent(forIRCProtocolURI location: String) -> URIIntent? {
		guard !location.isEmpty else {
			return nil
		}

		/* Basic input clean up. */
		let locationValue = (location.removingPercentEncoding ?? location)
			.trimmingCharacters(in: .whitespacesAndNewlines)

		/* This method extracts the path component of the URL from the input
		 string before turning the remaining pieces into an NSURL. */
		/* The URL may contain multiple sections proceeded by the pound sign (#),
		 which this method treats as channel, but NSURL aren't too friendly about. */
		let totalSlashCount = locationValue.reduce(into: 0) { count, character in
			if character == "/" {
				count += 1
			}
		}

		if totalSlashCount < 2 || totalSlashCount > 3 {
			return nil
		}

		var serverInfo = locationValue
		var channelInfo: String?

		if totalSlashCount == 3, let separator = locationValue.lastIndex(of: "/") {
			serverInfo = String(locationValue[..<separator])
			channelInfo = String(locationValue[locationValue.index(after: separator)...])
		}

		/* Now that channel information is no longer present in the URL,
		 we can pass it to NSURL to extract all other information. */
		guard let baseURL = URL(string: serverInfo),
		      let addressScheme = baseURL.scheme,
		      let serverAddress = baseURL.host
		else {
			return nil
		}

		if addressScheme == "glasstual" {
			return .glasstualAction(host: serverAddress, source: locationValue)
		}

		/* Continue normal parsing... */
		// Truncating here would silently connect to a different port than the
		// one the URI names (irc://host:99999 becomes 34463).
		guard let serverPortValue = UInt16(exactly: baseURL.port ?? Int(IRCConnectionDefaults.serverPort)) else {
			extrasLogger.error("Invalid internet port")

			return nil
		}
		var connectSecurely = false

		if addressScheme == "ircs" {
			connectSecurely = true
		}

		/* If we have made it to this point without this method returning,
		 then everything is going smooth so far. We have established our
		 server address, the URL scheme, and associated channel information. */
		/* We will now parse the actual channel information. */
		/* This method does not actually create the connection. It only formats
		 the input so that another can. Therefore, we do not have to take much
		 care with the channel information. Just a basic parse to establish if
		 the "needssl" token is present as well as the channel name having a
		 pound (#) sign in front of it. */
		let channelList = NSMutableString()

		if let channelInfo {
			var dataSections = channelInfo.components(separatedBy: ",").filter { $0.isEmpty == false }

			/* The trailing "needssl" token has to be recognised before the
			 five-channel cap is applied, otherwise a URI with more channels
			 than that silently downgrades to a plaintext connection. */
			if let lastSection = dataSections.last,
			   lastSection.caseInsensitiveCompare("needssl") == .orderedSame
			{
				connectSecurely = true

				dataSections.removeLast()
			}

			for section in dataSections.prefix(5) {
				var sectionCopy = section

				if (sectionCopy as NSString).hasPrefix("#") == false {
					sectionCopy = "#" + sectionCopy
				}

				channelList.append(sectionCopy)
				channelList.append(",")
			}

			/* Erase end commas */
			if channelList.length > 1 {
				channelList.deleteCharacters(in: NSRange(location: channelList.length - 1, length: 1))
			}
		}

		/* We have parsed every part of our URL. Build the final result and
		 pass it along. We are done here. */
		let resultValue = if connectSecurely {
			String(
				format: "-SSL %@:%hu",
				serverAddress,
				serverPortValue
			)
		} else {
			String(
				format: "%@:%hu",
				serverAddress,
				serverPortValue
			)
		}

		/* A URL is consider untrusted and will not auto connect */
		return .connect(URIConnectionIntent(
			serverInfo: resultValue,
			channelList: channelList.length > 0 ? channelList as String : nil
		))
	}

	/// The connection half of `intent(forIRCProtocolURI:)`; `nil` for
	/// `glasstual:` actions and malformed input.
	nonisolated static func connectionIntent(forIRCProtocolURI location: String) -> URIConnectionIntent? {
		guard case let .connect(intent) = intent(forIRCProtocolURI: location) else {
			return nil
		}

		return intent
	}

	enum URIIntent: Equatable {
		case connect(URIConnectionIntent)
		case glasstualAction(host: String, source: String)
	}

	struct URIConnectionIntent: Equatable {
		let serverInfo: String
		let channelList: String?
	}

	@objc(parseIRCProtocolURI:withDescriptor:)
	public static func parseIRCProtocolURI(_ location: String, withDescriptor _: NSAppleEventDescriptor?) {
		switch intent(forIRCProtocolURI: location) {
		case let .glasstualAction(host, source):
			performSpecialActionForGlasstualScheme(host, source: source)
		case let .connect(intent):
			createConnectionToServer(
				intent.serverInfo,
				channelList: intent.channelList,
				connectWhenCreated: false,
				mergeConnectionIfPossible: true,
				selectFirstChannelAdded: false
			)
		case nil:
			break
		}
	}

	// MARK: - Connection Creation

	@objc(createConnectionToServer:channelList:connectWhenCreated:)
	public static func createConnectionToServer(
		_ serverInfo: String,
		channelList: String?,
		connectWhenCreated: Bool
	) {
		createConnectionToServer(
			serverInfo,
			channelList: channelList,
			connectWhenCreated: connectWhenCreated,
			mergeConnectionIfPossible: false,
			selectFirstChannelAdded: false
		)
	}

	@objc(createConnectionToServer:channelList:connectWhenCreated:mergeConnectionIfPossible:selectFirstChannelAdded:)
	public static func createConnectionToServer(
		_ serverInfo: String,
		channelList: String?,
		connectWhenCreated: Bool,
		mergeConnectionIfPossible: Bool,
		selectFirstChannelAdded: Bool
	) {
		guard let request = connectionRequest(
			parsing: serverInfo,
			channelList: channelList,
			connectWhenCreated: connectWhenCreated,
			mergeConnectionIfPossible: mergeConnectionIfPossible,
			selectFirstChannelAdded: selectFirstChannelAdded
		) else {
			return
		}

		createConnectionToServer(request)
	}

	/// Parses the `[-SSL] host[:port] [password]` server-info form into a
	/// connection request. Pure; no side effects.
	nonisolated static func connectionRequest(
		parsing serverInfo: String,
		channelList: String?,
		connectWhenCreated: Bool,
		mergeConnectionIfPossible: Bool,
		selectFirstChannelAdded: Bool
	) -> ConnectionRequest? {
		guard !serverInfo.isEmpty else {
			return nil
		}

		/* Establish our variables */
		var serverAddress: String?
		var serverPort: UInt16 = IRCConnectionDefaults.serverPort
		var serverPassword: String?
		var connectSecurely = false

		/* Begin parsing */
		let serverInfoMutable = NSMutableString(string: serverInfo)

		/* Get our first token. A token is everything before the first
		 occurrence of a space character. getToken will get everything
		 before a space in a string, then erase the remaining content
		 of that string so that each call to getToken gives us the next
		 section of our string. */
		var tempStore = serverInfoMutable.ceToken

		/* Secure Socket Layer? */
		if tempStore.caseInsensitiveCompare("-SSL") == .orderedSame
			|| tempStore.caseInsensitiveCompare("-TLS") == .orderedSame
		{
			connectSecurely = true

			/* If the SSL define was our first token, we
			 go to our next token. */
			tempStore = serverInfoMutable.ceToken
		}

		/* Server Address */
		let openingBracket = tempStore.firstIndex(of: "[")
		let closingBracket = tempStore.firstIndex(of: "]")

		if let openingBracket,
		   let closingBracket,
		   openingBracket == tempStore.startIndex,
		   openingBracket < closingBracket
		{
			let addressStart = tempStore.index(after: openingBracket)
			let tempServerAddress = String(tempStore[addressStart ..< closingBracket])

			if tempServerAddress.isIPv6Address == false {
				extrasLogger.error(
					"Server address was surrounded by square brackets but the enclosed value was not an IPv6 address"
				)

				return nil
			}

			serverAddress = tempServerAddress

			tempStore = String(tempStore[tempStore.index(after: closingBracket)...])
		} else if openingBracket == nil, closingBracket == nil {
			/* Our server address did not contain brackets. Does it
			 contain a colon (:) which means a port is included? */
			if let colonPosition = tempStore.firstIndex(of: ":") {
				serverAddress = String(tempStore[..<colonPosition])

				/* We cut the server address out of our temporary store,
				 but left the colon and everything after it, in it. */
				tempStore = String(tempStore[colonPosition...])
			} else {
				serverAddress = tempStore
			}
		} else {
			/* If we have a opening bracket but no closing or any
			 combination of the two, then return this method as our
			 server address is already invalid. If there were not
			 brackets either, then we are not treating the server
			 as an IPv4 address so any colon will be considered
			 for port use only. */

			return nil
		}

		guard let parsedServerAddress = serverAddress,
		      (parsedServerAddress as NSString).isValidInternetAddress
		else {
			extrasLogger.error("Invalid internet address")

			return nil
		}

		serverAddress = parsedServerAddress.lowercased()

		/* Server Port */
		var tempServerPort: String?

		if tempStore.hasPrefix(":") {
			tempServerPort = String(tempStore.dropFirst())
		} else if serverInfoMutable.length > 0 {
			tempServerPort = serverInfoMutable.ceToken
		}

		if var tempServerPort {
			if tempServerPort.hasPrefix("+") {
				tempServerPort = String(tempServerPort.dropFirst())

				connectSecurely = true
			}

			guard let parsedPort = UInt16(tempServerPort), parsedPort > 0 else {
				extrasLogger.error("Invalid internet port")

				return nil
			}

			serverPort = parsedPort
		}

		/* Server Password */
		/* If our base is still not empty after taking out the token for the
		 server address and port, then we are going to treat that as the server
		 password. Anything after this token will be ignored completely. */
		if serverInfoMutable.length > 0 {
			tempStore = serverInfoMutable.ceToken

			serverPassword = tempStore
		}

		let channelListArray = parseChannelList(channelList)

		/* Create connection */
		guard let serverAddress else {
			return nil
		}

		return ConnectionRequest(
			serverAddress: serverAddress,
			serverPort: serverPort,
			serverPassword: serverPassword,
			connectSecurely: connectSecurely,
			channelList: channelListArray,
			connectWhenCreated: connectWhenCreated,
			mergeConnectionIfPossible: mergeConnectionIfPossible,
			selectFirstChannelAdded: selectFirstChannelAdded
		)
	}

	/// Splits a comma-separated channel list, dropping non-channel names and
	/// case-insensitive duplicates. `nil` when there is nothing to join.
	nonisolated static func parseChannelList(_ channelList: String?) -> [String]? {
		guard let channelList, channelList.isEmpty == false else {
			return nil
		}

		var parsedChannels: [String] = []

		for section in channelList.components(separatedBy: ",") {
			let channelName = section.trimmingCharacters(in: .whitespacesAndNewlines)

			if (channelName as NSString).isChannelName == false {
				continue
			}

			if parsedChannels.contains(where: {
				$0.caseInsensitiveCompare(channelName) == .orderedSame
			}) {
				continue
			}

			parsedChannels.append(channelName)
		}

		return parsedChannels
	}

	struct ConnectionRequest: Equatable {
		let serverAddress: String
		let serverPort: UInt16
		let serverPassword: String?
		let connectSecurely: Bool
		let channelList: [String]?
		let connectWhenCreated: Bool
		let mergeConnectionIfPossible: Bool
		let selectFirstChannelAdded: Bool
	}

	private static func createConnectionToServer(_ request: ConnectionRequest) {
		let serverAddress = request.serverAddress
		let serverPort = request.serverPort
		let serverPassword = request.serverPassword
		let connectSecurely = request.connectSecurely
		let channelList = request.channelList
		let connectWhenCreated = request.connectWhenCreated
		let mergeConnectionIfPossible = request.mergeConnectionIfPossible
		let selectFirstChannelAdded = request.selectFirstChannelAdded

		precondition(!serverAddress.isEmpty)
		precondition(serverPort > 0)

		let channelListCount = channelList?.count ?? 0

		/* If merging is enabled, try to find first possible client
		 by comparing server address values. */
		/* Merging is only performed if a channel is being joined. */
		var existingClient: IRCClient?

		if mergeConnectionIfPossible, channelListCount > 0 {
			existingClient = NSObject.applicationController().world.findClient(withServerAddress: serverAddress)
		}

		if let matchedClient = existingClient,
		   let channelList,
		   shouldMergeConnection(matchedClient, serverAddress: serverAddress, channelList: channelList) == false
		{
			existingClient = nil
		}

		/* Create new connection or merge into existing */
		if let existingClient {
			var firstChannelAdded: IRCChannel?

			for channelName in channelList! {
				let channel = existingClient.findChannelOrCreate(channelName, isPrivateMessage: false)

				if firstChannelAdded == nil {
					firstChannelAdded = channel
				}

				if connectWhenCreated, let channel {
					existingClient.join(channel)
				}
			}

			NSObject.applicationController().world.save()

			if selectFirstChannelAdded, let firstChannelAdded {
				if let treeItem = (firstChannelAdded as AnyObject) as? IRCTreeItem {
					NSObject.applicationController().mainWindow.select(treeItem)
				}
			}
		} else {
			let baseConfig = IRCClientConfigMutable()

			baseConfig.connectionName = serverAddress

			let server = MutableServer()

			server.serverAddress = serverAddress
			server.serverPort = serverPort

			server.prefersSecuredConnection = connectSecurely

			if let serverPassword {
				server.serverPassword = serverPassword
			}

			guard let serverCopy = server.copy(asMutable: false, uniquing: false) as? Server else {
				preconditionFailure("Server copies must preserve their model type")
			}

			baseConfig.setValue([serverCopy], forKey: "serverList")

			var channelListConfigs = [Any]()

			channelListConfigs.reserveCapacity(channelListCount)

			for channelName in channelList ?? [] {
				let channelConfig = ChannelConfig.seed(withName: channelName)

				channelListConfigs.append(channelConfig)
			}

			baseConfig.setValue(channelListConfigs, forKey: "channelList")

			let client = NSObject.applicationController().world.createClient(
				with: bridgeClientConfigToObjectiveC(baseConfig),
				reload: true
			)

			NSObject.applicationController().world.save()

			if connectWhenCreated {
				client.connect()
			}

			if selectFirstChannelAdded {
				client.selectFirstChannelInChannelList()
			}
		}
	}

	private static func shouldMergeConnection(
		_ client: IRCClient,
		serverAddress: String,
		channelList: [String]
	) -> Bool {
		let includesMultipleChannels = channelList.count > 1
		let channelNames = includesMultipleChannels ? channelList.joined(separator: ", ") : channelList[0]

		return TDCAlert.modalAlert(
			withMessage: PromptStrings.ConnectionLink.existingConnectionBody(
				name: client.name,
				includesMultipleChannels: includesMultipleChannels
			),
			title: PromptStrings.ConnectionLink.title(
				serverAddress: serverAddress,
				channelNames: channelNames,
				includesMultipleChannels: includesMultipleChannels
			),
			defaultButton: PromptStrings.ConnectionLink.useExistingConnectionButtonTitle,
			alternateButton: PromptStrings.ConnectionLink.createNewConnectionButtonTitle
		)
	}
}
