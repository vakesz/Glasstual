/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit

#if !DEBUG
	if TXApplication.checkForOtherCopiesOfGlasstualRunning() == false {
		exit(EXIT_SUCCESS)
	}
#endif

NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
