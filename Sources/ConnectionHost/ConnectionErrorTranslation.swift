// Copyright (c) 2018 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
import Network

extension ConnectionError {
	/// The connection error `error` is reported to the application as. A
	/// Network.framework failure carries its own vocabulary — a DNS status, a
	/// POSIX number, a TLS alert — and this is where each becomes one of ours.
	static func translating(_ error: Error) -> ConnectionError {
		switch error {
		case let error as ConnectionError:
			error
		case let .dns(errorCode) as NWError:
			ConnectionError(nwDNSError: errorCode)
		case let .posix(errorCode) as NWError:
			ConnectionError(nwPOSIXError: errorCode.rawValue)
		case let .tls(errorCode) as NWError:
			ConnectionError(tlsError: Int(errorCode))
		case NWError.wifiAware:
			.other(message: String(localized: .ConnectionErrors.wifiAwareError))
		case let error as NWError:
			.other(message: error.localizedDescription)
		default:
			.socket(error: error as NSError)
		}
	}
}

private extension ConnectionError {
	/// The reason named beside the numeric code in a DNS error. `kDNSServiceErr_NoError`
	/// has no entry: `NWError.dns` is only ever built from a failure.
	static let dnsErrorReasons: [Int: LocalizedStringResource] = [
		kDNSServiceErr_NoSuchName: .ConnectionErrors.dnsReasonNoSuchName,
		kDNSServiceErr_NoMemory: .ConnectionErrors.dnsReasonNoMemory,
		kDNSServiceErr_BadParam: .ConnectionErrors.dnsReasonBadParameter,
		kDNSServiceErr_BadReference: .ConnectionErrors.dnsReasonBadReference,
		kDNSServiceErr_BadState: .ConnectionErrors.dnsReasonBadState,
		kDNSServiceErr_BadFlags: .ConnectionErrors.dnsReasonBadFlags,
		kDNSServiceErr_Unsupported: .ConnectionErrors.dnsReasonUnsupported,
		kDNSServiceErr_NotInitialized: .ConnectionErrors.dnsReasonNotInitialized,
		kDNSServiceErr_AlreadyRegistered: .ConnectionErrors.dnsReasonAlreadyRegistered,
		kDNSServiceErr_NameConflict: .ConnectionErrors.dnsReasonNameConflict,
		kDNSServiceErr_Invalid: .ConnectionErrors.dnsReasonInvalid,
		kDNSServiceErr_Firewall: .ConnectionErrors.dnsReasonFirewall,
		kDNSServiceErr_Incompatible: .ConnectionErrors.dnsReasonIncompatible,
		kDNSServiceErr_BadInterfaceIndex: .ConnectionErrors.dnsReasonBadInterfaceIndex,
		kDNSServiceErr_Refused: .ConnectionErrors.dnsReasonRefused,
		kDNSServiceErr_NoSuchRecord: .ConnectionErrors.dnsReasonNoSuchRecord,
		kDNSServiceErr_NoAuth: .ConnectionErrors.dnsReasonNoAuthentication,
		kDNSServiceErr_NoSuchKey: .ConnectionErrors.dnsReasonNoSuchKey,
		kDNSServiceErr_NATTraversal: .ConnectionErrors.dnsReasonNatTraversal,
		kDNSServiceErr_DoubleNAT: .ConnectionErrors.dnsReasonDoubleNat,
		kDNSServiceErr_BadTime: .ConnectionErrors.dnsReasonBadTime,
		kDNSServiceErr_BadSig: .ConnectionErrors.dnsReasonBadSignature,
		kDNSServiceErr_BadKey: .ConnectionErrors.dnsReasonBadKey,
		kDNSServiceErr_Transient: .ConnectionErrors.dnsReasonTransient,
		kDNSServiceErr_ServiceNotRunning: .ConnectionErrors.dnsReasonServiceNotRunning,
		kDNSServiceErr_NATPortMappingUnsupported: .ConnectionErrors.dnsReasonNatPortMappingUnsupported,
		kDNSServiceErr_NATPortMappingDisabled: .ConnectionErrors.dnsReasonNatPortMappingDisabled,
		kDNSServiceErr_NoRouter: .ConnectionErrors.dnsReasonNoRouter,
		kDNSServiceErr_PollingMode: .ConnectionErrors.dnsReasonPollingMode,
		kDNSServiceErr_Timeout: .ConnectionErrors.dnsReasonTimeout,
	]

	init(nwDNSError: DNSServiceErrorType) {
		let errorCode = Int(nwDNSError)
		let errorReason = String(
			localized: Self.dnsErrorReasons[errorCode] ?? .ConnectionErrors.errorReasonUnknown
		)

		let errorMessage = ConnectionErrorLocalization.formatted(
			.ConnectionErrors.dnsError(errorReason, errorCode),
			errorReason,
			errorCode
		)

		let nsError = NSError(
			domain: "NWErrorDomainDNS",
			code: errorCode,
			userInfo: [NSLocalizedDescriptionKey: errorMessage]
		)

		self = .socket(error: nsError)
	}

	init(nwPOSIXError: Int32) {
		let errorCode = Int(nwPOSIXError)

		let errorReason = if let errorReasonC = strerror(nwPOSIXError) {
			String(cString: errorReasonC)
		} else {
			String(localized: .ConnectionErrors.errorReasonUnknown)
		}

		let errorMessage = ConnectionErrorLocalization.formatted(
			.ConnectionErrors.posixError(errorReason, errorCode),
			errorReason,
			errorCode
		)

		let nsError = NSError(
			domain: "NWErrorDomainPOSIX",
			code: errorCode,
			userInfo: [NSLocalizedDescriptionKey: errorMessage]
		)

		self = .socket(error: nsError)
	}
}

private enum ConnectionErrorLocalization {
	static func formatted(_ resource: LocalizedStringResource, _ arguments: CVarArg...) -> String {
		Bundle(for: ConnectionErrorLocalizationBundleToken.self)
			.localizedString(for: resource, arguments: arguments)
	}
}

private final class ConnectionErrorLocalizationBundleToken {}
