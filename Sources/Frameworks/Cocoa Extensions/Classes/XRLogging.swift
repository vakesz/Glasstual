/* *********************************************************************
 *
 *           Copyright (c) 2024 Codeux Software, LLC
 *     Please see ACKNOWLEDGEMENT for additional information.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 *  * Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *  * Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *  * Neither the name of "Codeux Software, LLC", nor the names of its
 *    contributors may be used to endorse or promote products derived
 *    from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 *********************************************************************** */

import Foundation
@_exported import os

/* *********************************************************************
 *
 *         Copyright (c) 2015 - 2020 Codeux Software, LLC
 *     Please see ACKNOWLEDGEMENT for additional information.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 *  * Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *  * Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *  * Neither the name of "Codeux Software, LLC", nor the names of its
 *    contributors may be used to endorse or promote products derived
 *    from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 *********************************************************************** */

private enum LegacyLoggingStorage {
	static let frameworkSubsystem = OSLog(
		subsystem: "com.vakesz.glasstual.frameworks.CocoaExtensions",
		category: "Framework"
	)

	nonisolated(unsafe) static var defaultSubsystem: OSLog?
}

@_cdecl("_CSFrameworkInternalLogSubsystem")
public func _CSFrameworkInternalLogSubsystem() -> OSLog {
	LegacyLoggingStorage.frameworkSubsystem
}

@_cdecl("_LogToConsoleDefaultSubsystem")
public func _LogToConsoleDefaultSubsystem() -> OSLog {
	LegacyLoggingStorage.defaultSubsystem ?? .default
}

@_cdecl("_LogToConsoleSetDefaultSubsystem")
public func _LogToConsoleSetDefaultSubsystem(_ subsystem: OSLog?) {
	LegacyLoggingStorage.defaultSubsystem = subsystem
	LoggingProxy.defaultSubsystem = subsystem
}

@_cdecl("_LogToConsoleSetDefaultSubsystemToMainBundle")
public func _LogToConsoleSetDefaultSubsystemToMainBundle(_ category: NSString) {
	let subsystem = OSLog(
		subsystem: Bundle.main.bundleIdentifier ?? "com.vakesz.glasstual",
		category: category as String
	)

	_LogToConsoleSetDefaultSubsystem(subsystem)
}

@_cdecl("_LogToConsoleFormattedStackTrace")
public func _LogToConsoleFormattedStackTrace(_ trace: NSArray) -> NSString {
	trace.componentsJoined(by: "\n") as NSString
}

public func _LogStackTraceOfTypeSwiftShim(_ type: OSLogType, _ subsystem: OSLog?) {
	let logger: Logger = if let subsystem {
		Logger(subsystem)
	} else if let defaultSubsystem = Logging.defaultSubsystem {
		defaultSubsystem
	} else {
		Logger()
	}

	let stackTrace = _LogToConsoleFormattedStackTrace(Thread.callStackSymbols as NSArray) as String
	logger.log(level: type, "Stack trace:\n\(stackTrace, privacy: .private)")
}

public class Logging {
	///
	/// Logger used for logging
	///
	/// Generally speaking, app or service will have set this
	/// very early on during initialization so while it is possible
	/// for it to be nil, it is very unlikely. Assume it's not.
	///
	/// Set once during process start-up and read-only afterwards.
	public nonisolated(unsafe) static var defaultSubsystem: Logger?

	///
	/// Set default subsystem to identifier of main bundle
	/// with category.
	///
	@inlinable
	public static func setDefaultSubsystem(toMainBundleCategory category: String) {
		_LogToConsoleSetDefaultSubsystemToMainBundle(category as NSString)
	}

	///
	/// Log stack trace of type in optional subsystem
	///
	@inlinable
	public static func logStackTrace(ofType type: OSLogType = .default, inSubsystem subsystem: OSLog? = nil) {
		_LogStackTraceOfTypeSwiftShim(type, subsystem)
	}

	///
	/// Subsystem used by Cocoa Extensions
	///
	nonisolated(unsafe) static var frameworkSubsystem: Logger? = Logger(_CSFrameworkInternalLogSubsystem())
}

///
/// Proxy class for C API for setting logging subsystem
///
@objc(XRLoggingProxy)
class LoggingProxy: NSObject {
	@objc
	static var defaultSubsystem: OSLog? {
		get {
			fatalError("Access default logging subsystem through C API")
		}
		set {
			if let newValue {
				Logging.defaultSubsystem = Logger(newValue)
			} else {
				Logging.defaultSubsystem = Logger() // Default
			}
		}
	}
}
