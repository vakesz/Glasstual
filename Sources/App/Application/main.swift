/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit

/* NSApplicationMain performs AppKit's native process registration and launch
 handoff. The principal Application class owns the code-only delegate and menu
 graph, so no application nib is required. */
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
