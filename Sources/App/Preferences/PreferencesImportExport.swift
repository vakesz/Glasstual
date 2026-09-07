/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import Foundation

/** What a configuration file is called when the save panel offers one.

 Nothing else is left here. Reading and writing a configuration goes through
 `PreferencesTransferSession`, which previews a plan, takes a recovery backup
 and reconciles the live world; a second entry point that wrote straight into
 the defaults store would be a way around all three. */
public nonisolated enum PreferencesImportExport { // nonisolated: value
	public static let defaultArchiveFilename = "GlasstualPreferences.plist"
}
