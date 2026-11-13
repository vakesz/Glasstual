# Scrollback row fixture

`ScrollbackPayload-v1.plist` is a synthetic `ChatLineStoredPayload` version 1,
the property list that `ChatLine.scrollbackEntry(forView:)` stores in
`ScrollbackEntry.lineData`. It includes optional message identifiers, keyword
lists and a reaction.

`ChatLineTests` checks every decoded field and the re-encoded field names, so
keep the fixture consistent with `ChatLine.CodingKeys`. Tests read it from the
source tree through `#filePath`; it is not a bundled resource.
