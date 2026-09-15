/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import CocoaExtensions
import Foundation
import GlasstualPluginKit
import os
import Security

/** Whether a plugin bundle may load: it has to speak the current plugin
 interface, and either ship inside the application or carry a valid signature
 from the Team ID that signed it. Every refusal is logged with its reason. */
nonisolated enum PluginBundleValidation { // nonisolated: value
	private static let logger = Logger(
		subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
		category: "PluginManager"
	)

	static let interfaceVersionMetadataKey = "GlasstualPluginInterfaceVersion"
	static let currentInterfaceVersion = 1

	/// A bundle predating the interface-version key declares a host version
	/// instead. The major it has to name is the one the contract itself names.
	static let legacyMinimumMajorVersion = String(
		PluginCompatibility.minimumHostVersion.prefix { $0 != "." }
	)

	static func supportsCurrentPluginProtocol(_ bundle: Bundle) -> Bool {
		if let declaredVersion = bundle.object(forInfoDictionaryKey: interfaceVersionMetadataKey) {
			guard case let .integer(version)? = PropertyListValue(propertyList: declaredVersion),
			      version == currentInterfaceVersion
			else {
				logger.error("Unsupported plugin interface in \(bundle.bundlePath, privacy: .public)")
				return false
			}
			return true
		}

		guard let minimumVersion = bundle.infoDictionary?["MinimumGlasstualVersion"] as? String else {
			logger.error(
				"Refusing to load the bundle at “\(bundle.bundlePath, privacy: .public)“ because it does not declare MinimumGlasstualVersion; the current minimum is \(PluginCompatibility.minimumHostVersion, privacy: .public)"
			)
			return false
		}

		/* Any 8.x.y is accepted, not just the exact minimum: a bundle built
		 against an earlier point release of the same host contract still loads,
		 and the interface-version key above is what pins the contract itself. */
		let components = minimumVersion.split(separator: ".", omittingEmptySubsequences: false)
		guard components.count == 3,
		      components.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
		      components.first.map(String.init) == legacyMinimumMajorVersion
		else {
			logger.error(
				"Refusing legacy plugin metadata in \(bundle.bundlePath, privacy: .public): \(minimumVersion, privacy: .public)"
			)
			return false
		}

		return true
	}

	// MARK: - Signature Validation

	static func isBundledExtension(_ bundle: Bundle) -> Bool {
		let applicationPath = (Bundle.main.bundlePath as NSString).standardizingPath
		let bundlePath = (bundle.bundlePath as NSString).standardizingPath

		return bundlePath.hasPrefix(applicationPath + "/")
	}

	private static let applicationTeamIdentifier: String? = {
		var code: SecCode?
		guard SecCodeCopySelf(SecCSFlags(rawValue: 0), &code) == errSecSuccess, let code else {
			return nil
		}
		var staticCode: SecStaticCode?
		guard SecCodeCopyStaticCode(code, SecCSFlags(rawValue: 0), &staticCode) == errSecSuccess,
		      let staticCode
		else {
			return nil
		}

		return teamIdentifier(of: staticCode)
	}()

	private static func teamIdentifier(of staticCode: SecStaticCode) -> String? {
		var signingInformation: CFDictionary?
		let status = SecCodeCopySigningInformation(
			staticCode,
			SecCSFlags(rawValue: kSecCSSigningInformation),
			&signingInformation
		)

		guard status == errSecSuccess, let signingInformation else {
			return nil
		}

		let information = signingInformation as NSDictionary
		let team = information[kSecCodeInfoTeamIdentifier as String] as? String

		guard let team, team.isEmpty == false else {
			return nil
		}

		return team
	}

	private static func error(withStatus status: OSStatus) -> NSError {
		let message = SecCopyErrorMessageString(status, nil) as String? ?? "Unknown error"

		return NSError(
			domain: NSOSStatusErrorDomain,
			code: Int(status),
			userInfo: [NSLocalizedDescriptionKey: message]
		)
	}

	/// Whether `bundle` carries a valid signature from the same Team ID that
	/// signed the running application. Every refusal is logged with its reason.
	static func isSignedByThisApplication(_ bundle: Bundle) -> Bool {
		do {
			try validateSignature(of: bundle)
			return true
		} catch {
			logger.error(
				"Refusing to load the bundle at “\(bundle.bundlePath, privacy: .public)“ because its signature is missing or is not ours: \(error.localizedDescription, privacy: .public)"
			)
			return false
		}
	}

	private static func validateSignature(of bundle: Bundle) throws {
		var staticCode: SecStaticCode?
		var status = SecStaticCodeCreateWithPath(
			bundle.bundleURL as CFURL,
			SecCSFlags(rawValue: 0),
			&staticCode
		)

		guard status == errSecSuccess, let staticCode else {
			throw error(withStatus: status)
		}

		let validationFlags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate)
		try checkValidity(of: staticCode, flags: validationFlags, requirement: nil)

		guard let team = teamIdentifier(of: staticCode) else {
			throw error(withStatus: errSecCSSignatureUntrusted)
		}

		guard let applicationTeam = applicationTeamIdentifier, team == applicationTeam else {
			throw error(withStatus: errSecCSSignatureUntrusted)
		}

		let requirementString =
			"anchor apple generic and certificate leaf[subject.OU] = \"\(applicationTeam)\""

		var requirement: SecRequirement?
		status = SecRequirementCreateWithString(
			requirementString as CFString,
			SecCSFlags(rawValue: 0),
			&requirement
		)

		guard status == errSecSuccess, let requirement else {
			throw error(withStatus: status)
		}

		try checkValidity(of: staticCode, flags: validationFlags, requirement: requirement)
	}

	private static func checkValidity(
		of staticCode: SecStaticCode,
		flags: SecCSFlags,
		requirement: SecRequirement?
	) throws {
		var validityError: Unmanaged<CFError>?
		let status = SecStaticCodeCheckValidityWithErrors(
			staticCode,
			flags,
			requirement,
			&validityError
		)

		guard status != errSecSuccess else {
			/* The out-parameter is populated on failure only, but release it
			 defensively so a success path can never leak it. */
			validityError?.release()
			return
		}

		guard let validityError else {
			throw error(withStatus: status)
		}

		throw validityError.takeRetainedValue() as Error
	}
}
