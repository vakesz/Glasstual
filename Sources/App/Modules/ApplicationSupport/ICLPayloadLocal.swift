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

import Foundation
import os

private let payloadLogger = Logger(
	subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
	category: "ICLPayload"
)

extension ICLPayload {
	@objc(_resourcesTemporaryLocation)
	func _resourcesTemporaryLocation() -> String {
		let sourcePath = TXSharedApplication.sharedThemeController().temporaryPath as NSString
		let basePath = sourcePath.appendingPathComponent("/ICLPayload-Resources/")
		TPCPathInfo._createDirectory(atPath: basePath)
		return basePath
	}

	/** WebKit2 uses sandboxed processes. Copy resource files into the
	 application's temporary folder so WebKit can access them. */
	@objc(_copyResourcesToTemporaryLocation:)
	func _copyResources(toTemporaryLocation resources: [URL]?) -> [String]? {
		guard let resources else {
			return nil
		}

		let basePath = _resourcesTemporaryLocation() as NSString
		let fileManager = FileManager.default

		func copyOperation(_ resourceURL: URL) -> String {
			guard resourceURL.isFileURL else {
				return resourceURL.absoluteString
			}

			let resourcePath = resourceURL.relativePath
			let filename = "\((resourcePath as NSString).sha256).\((resourcePath as NSString).pathExtension)"
			let destinationPath = basePath.appendingPathComponent(filename)

			if fileManager.fileExists(atPath: destinationPath) {
				return destinationPath
			}

			do {
				try fileManager.copyItem(atPath: resourcePath, toPath: destinationPath)
			} catch {
				let tildePath = (resourcePath as NSString).standardizedTildePath ?? resourcePath
				payloadLogger.error(
					"Copy operation for '\(tildePath, privacy: .public)' failed with error: \(error.localizedDescription, privacy: .public)"
				)
			}

			return destinationPath
		}

		return resources.map { copyOperation($0) }
	}

	@objc public var javaScriptObject: [String: Any] {
		let dic = NSMutableDictionary()

		dic.setUnsignedInteger(UInt(contentLength), forKey: "contentLength")
		dic["contentSize"] = [
			"width": contentSize.width,
			"height": contentSize.height,
		]

		dic.maybeSetObject(_copyResources(toTemporaryLocation: styleResources), forKey: "styleResources")
		dic.maybeSetObject(_copyResources(toTemporaryLocation: scriptResources), forKey: "scriptResources")
		dic["html"] = html

		if let entrypoint {
			dic["entrypoint"] = entrypoint
			/* Use the property (not storage) so default entrypoint payload values are applied. */
			dic["entrypointPayload"] = entrypointPayload
		}

		dic["url"] = url
		dic["urlToInline"] = urlToInline
		dic["lineNumber"] = lineNumber
		dic["uniqueIdentifier"] = uniqueIdentifier
		dic.setUnsignedInteger(index, forKey: "index")

		return dic as! [String: Any]
	}
}
