/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit

/* The duplicate-instance check lives in -applicationWillFinishLaunching. It
 puts an alert on screen, and running one before NSApplicationMain forces
 NSApplication.shared into existence as a plain NSApplication rather than the
 principal class named by the bundle. */
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
