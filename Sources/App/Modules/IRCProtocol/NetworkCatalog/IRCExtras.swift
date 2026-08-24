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
import os

private let extrasLogger = Logger(
	subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
	category: "IRCExtras"
)

@objc(IRCExtras)
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

		let menuController = NSObject.masterController().menuController

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

	@objc(parseIRCProtocolURI:withDescriptor:)
	public static func parseIRCProtocolURI(_ location: String, withDescriptor _: NSAppleEventDescriptor?) {
		precondition(!location.isEmpty)

		/* Basic input clean up. */
		var locationValue = (location as NSString).percentDecoded ?? location
		locationValue = (locationValue as NSString).trim

		/* This method extracts the path component of the URL from the input
		 string before turning the remaining pieces into an NSURL. */
		/* The URL may contain multiple sections proceeded by the pound sign (#),
		 which this method treats as channel, but NSURL aren't too friendly about. */
		let totalSlashCount = (locationValue as NSString).occurrences(ofCharacter: UniChar("/".utf16.first!))

		if totalSlashCount < 2 || totalSlashCount > 3 {
			return
		}

		var serverInfo = locationValue
		var channelInfo: String?

		if totalSlashCount == 3 {
			let backwardRange = (locationValue as NSString).range(of: "/", options: .backwards)

			if backwardRange.location != NSNotFound {
				serverInfo = (locationValue as NSString).substring(to: backwardRange.location)
				channelInfo = (locationValue as NSString).substring(after: UInt(backwardRange.location))
			}
		}

		/* Now that channel information is no longer present in the URL,
		 we can pass it to NSURL to extract all other information. */
		guard let baseURL = URL(string: serverInfo),
		      let addressScheme = baseURL.scheme,
		      let serverAddress = baseURL.host
		else {
			return
		}

		if addressScheme == "glasstual" {
			performSpecialActionForGlasstualScheme(serverAddress, source: locationValue)

			return
		}

		/* Continue normal parsing... */
		let serverPortValue = UInt16(truncatingIfNeeded: baseURL.port ?? Int(IRCConnectionDefaultServerPort))
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
			let dataSections = (channelInfo as NSString).split(",")
			let dataSectionsCount = dataSections.count

			for (index, section) in dataSections.enumerated() {
				if section.isEmpty {
					continue
				}

				if index > 4 {
					break
				}

				let isLastObject = (index + 1) == dataSectionsCount

				if isLastObject, (section as NSString).isEqual(toStringIgnoringCase: "needssl") {
					connectSecurely = true

					continue
				}

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
		createConnectionToServer(
			resultValue,
			channelList: channelList.length > 0 ? channelList as String : nil,
			connectWhenCreated: false,
			mergeConnectionIfPossible: true,
			selectFirstChannelAdded: false
		)
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
		precondition(!serverInfo.isEmpty)

		/* Establish our variables */
		var serverAddress: String?
		var serverPort: UInt16 = IRCConnectionDefaultServerPort
		var serverPassword: String?
		var connectSecurely = false

		/* Begin parsing */
		let serverInfoMutable = NSMutableString(string: serverInfo)

		/* Get our first token. A token is everything before the first
		 occurrence of a space character. getToken will get everything
		 before a space in a string, then erase the remaining content
		 of that string so that each call to getToken gives us the next
		 section of our string. */
		var tempStore = serverInfoMutable.token

		/* Secure Socket Layer? */
		if (tempStore as NSString).isEqual(toStringIgnoringCase: "-SSL")
			|| (tempStore as NSString).isEqual(toStringIgnoringCase: "-TLS")
		{
			connectSecurely = true

			/* If the SSL define was our first token, we
			 go to our next token. */
			tempStore = serverInfoMutable.token
		}

		/* Server Address */
		let openingBracketPosition = (tempStore as NSString).stringPosition("[") + 1
		let closingBracketPosition = (tempStore as NSString).stringPosition("]")

		let hasOpeningBracket = openingBracketPosition == 1 && openingBracketPosition < closingBracketPosition
		let hasClosingBracket = closingBracketPosition > 0 && openingBracketPosition < closingBracketPosition

		if hasOpeningBracket, hasClosingBracket {
			let serverAddressRange = NSRange(
				location: openingBracketPosition,
				length: closingBracketPosition - openingBracketPosition
			)

			let tempServerAddress = (tempStore as NSString).substring(with: serverAddressRange)

			if (tempServerAddress as NSString).isIPv6Address == false {
				extrasLogger.error(
					"Server address was surrounded by square brackets but the enclosed value was not an IPv6 address"
				)

				return
			}

			serverAddress = tempServerAddress

			tempStore = (tempStore as NSString).substring(after: UInt(closingBracketPosition))
		} else if hasOpeningBracket == false, hasClosingBracket == false {
			/* Our server address did not contain brackets. Does it
			 contain a colon (:) which means a port is included? */
			let colonPosition = (tempStore as NSString).stringPosition(":")

			if colonPosition > -1 {
				serverAddress = (tempStore as NSString).substring(to: colonPosition)

				/* We cut the server address out of our temporary store,
				 but left the colon and everything after it, in it. */
				tempStore = (tempStore as NSString).substring(from: colonPosition)
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

			return
		}

		guard let parsedServerAddress = serverAddress,
		      (parsedServerAddress as NSString).isValidInternetAddress
		else {
			extrasLogger.error("Invalid internet address")

			return
		}

		serverAddress = (parsedServerAddress as NSString).lowercased

		/* Server Port */
		var tempServerPort: String?

		if (tempStore as NSString).hasPrefix(":") {
			tempServerPort = (tempStore as NSString).substring(from: 1)
		} else if serverInfoMutable.length > 0 {
			tempServerPort = serverInfoMutable.token
		}

		if var tempServerPort {
			if (tempServerPort as NSString).hasPrefix("+") {
				tempServerPort = (tempServerPort as NSString).substring(from: 1)

				connectSecurely = true
			}

			if (tempServerPort as NSString).isValidInternetPort == false {
				extrasLogger.error("Invalid internet port")

				return
			}

			serverPort = UInt16((tempServerPort as NSString).integerValue)
		}

		/* Server Password */
		/* If our base is still not empty after taking out the token for the
		 server address and port, then we are going to treat that as the server
		 password. Anything after this token will be ignored completely. */
		if serverInfoMutable.length > 0 {
			tempStore = serverInfoMutable.token

			serverPassword = tempStore
		}

		/* Convert channel list string into array of configurations */
		var channelListArray: [String]?

		if let channelList, channelList.isEmpty == false {
			channelListArray = []

			let dataSections = (channelList as NSString).split(",")

			for section in dataSections {
				let channelName = (section as NSString).trim

				if (channelName as NSString).isChannelName == false {
					continue
				}

				if (channelListArray! as NSArray).containsObjectIgnoringCase(channelName) {
					continue
				}

				channelListArray!.append(channelName)
			}
		}

		/* Create connection */
		createConnectionToServer(
			serverAddress!,
			serverPort: serverPort,
			serverPassword: serverPassword,
			connectSecurely: connectSecurely,
			channelList: channelListArray,
			connectWhenCreated: connectWhenCreated,
			mergeConnectionIfPossible: mergeConnectionIfPossible,
			selectFirstChannelAdded: selectFirstChannelAdded
		)
	}

	private static var isRunningUnitTests: Bool {
		ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
	}

	private static func createConnectionToServer(
		_ serverAddress: String,
		serverPort: UInt16,
		serverPassword: String?,
		connectSecurely: Bool,
		channelList: [String]?,
		connectWhenCreated: Bool,
		mergeConnectionIfPossible: Bool,
		selectFirstChannelAdded: Bool
	) {
		precondition(!serverAddress.isEmpty)
		precondition(serverPort > 0)

		/* Unit tests load into Glasstual.app (TEST_HOST). Never mutate the
		 live connection list or present merge prompts from that context. */
		if isRunningUnitTests {
			return
		}

		let channelListCount = channelList?.count ?? 0

		/* If merging is enabled, try to find first possible client
		 by comparing server address values. */
		/* Merging is only performed if a channel is being joined. */
		var existingClient: IRCClient?

		if mergeConnectionIfPossible, channelListCount > 0 {
			existingClient = NSObject.masterController().world.findClient(withServerAddress: serverAddress)
		}

		if existingClient != nil {
			let mergeConnection: Bool

			if channelListCount > 1 {
				let channelListFormatted = channelList!.joined(separator: ", ")

				mergeConnection = TDCAlert.modalAlert(
					withMessage: LocalizedKey("Prompts[a9z-9f]", existingClient!.name),
					title: LocalizedKey("Prompts[pnc-ew]", serverAddress, channelListFormatted),
					defaultButton: LocalizedKey("Prompts[0hh-sl]"),
					alternateButton: LocalizedKey("Prompts[sv9-8s]")
				)
			} else {
				mergeConnection = TDCAlert.modalAlert(
					withMessage: LocalizedKey("Prompts[mx1-qz]", existingClient!.name),
					title: LocalizedKey("Prompts[3l6-3z]", serverAddress, channelList!.first!),
					defaultButton: LocalizedKey("Prompts[sl5-rf]"),
					alternateButton: LocalizedKey("Prompts[xca-5h]")
				)
			}

			// YES = default button (create new connection)
			if mergeConnection == false {
				existingClient = nil
			}
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

			NSObject.masterController().world.save()

			if selectFirstChannelAdded, let firstChannelAdded {
				NSObject.masterController().mainWindow.select(firstChannelAdded)
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

			let serverCopy = server.copy(asMutable: false, uniquing: false) as! Server

			baseConfig.setValue([serverCopy], forKey: "serverList")

			var channelListConfigs = [Any]()

			channelListConfigs.reserveCapacity(channelListCount)

			for channelName in channelList ?? [] {
				let channelConfig = IRCChannelConfig.seed(withName: channelName)

				channelListConfigs.append(channelConfig)
			}

			baseConfig.setValue(channelListConfigs, forKey: "channelList")

			let client = NSObject.masterController().world.createClient(
				with: baseConfig,
				reload: true
			)

			NSObject.masterController().world.save()

			if connectWhenCreated {
				client.connect()
			}

			if selectFirstChannelAdded {
				client.selectFirstChannelInChannelList()
			}
		}
	}
}
