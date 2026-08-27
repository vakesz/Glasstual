/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit

#if !DEBUG
	if Application.shouldContinueLaunching() == false {
		exit(EXIT_SUCCESS)
	}
#endif

_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
