/* Stand-ins for the handful of names the preference declarations reference
 from elsewhere in the application.

 The generator compiles the declarations on their own -- the alternative is
 linking the whole application into a build phase of the application -- so the
 few constants they borrow have to come from somewhere. Each one is a stored
 preference *name*, so a stand-in that drifts from the real declaration writes
 the wrong name into the plists, and `PreferenceCatalogTests` fails: that test
 compares the checked-in files against the application's own
 `Preferences.GeneratedResources`, where these names come from the real
 declaration. A stale stand-in is therefore caught by the test rather than
 shipped. */

import Foundation

/// `Sources/App/Protocol/Presence/IRCWorld.swift`
let IRCWorldClientListDefaultsKey = "World Controller Client Configurations"
